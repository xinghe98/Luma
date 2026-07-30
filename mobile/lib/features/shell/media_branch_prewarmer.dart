// 媒体分支预热器在首页稳定后的空闲时段准备首屏数据和少量缩略图。
// 它与 MediaController、CatalogStore 和 ApiSession 协作，并按会话代数隔离缓存。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/controllers/media_controller.dart';
import '../../core/theme.dart';
import '../../data/api/api_session.dart';
import '../../data/models/api_catalog.dart';
import '../../data/models/media_filter.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import '../catalog/catalog_store.dart';

/// 把预热图片交给 Flutter 图片缓存；测试可注入无网络实现。
typedef MediaBranchImagePrecache =
    Future<void> Function(ImageProvider<Object> provider, BuildContext context);

/// 在不创建路由分支的前提下，缓存媒体入口可直接使用的首屏数据。
final class MediaBranchPrewarmer {
  /// 创建会话级预热器；实际网络和图片工作只有在 [schedule] 或 [warm] 后启动。
  MediaBranchPrewarmer({
    required MediaController media,
    required CatalogStore catalog,
    required ApiSession session,
    MediaBranchImagePrecache? precacheImage,
  }) : _media = media,
       _catalog = catalog,
       _session = session,
       _precacheImage = precacheImage ?? _defaultPrecacheImage;

  final MediaController _media;
  final CatalogStore _catalog;
  final ApiSession _session;
  final MediaBranchImagePrecache _precacheImage;

  List<MediaItem> _photos = const [];
  final Map<CatalogKind, List<CatalogItem>> _catalogItems = {};
  final Set<CatalogKind> _catalogReady = {};
  Future<void>? _inflight;
  int? _epoch;
  int _generation = 0;
  bool _scheduled = false;
  bool _photosReady = false;
  bool _disposed = false;

  /// 返回图片库预热快照；尚未完成或会话已变化时为空。
  List<MediaItem> get photos {
    _syncEpoch();
    return _photos;
  }

  /// 返回指定影视类型的预热快照；尚未完成或会话已变化时为空。
  List<CatalogItem> catalogItems(CatalogKind kind) {
    _syncEpoch();
    return _catalogItems[kind] ?? const [];
  }

  /// 把预热任务排到调度器空闲队列；无活动服务器或已有任务时不重复排队。
  bool schedule(BuildContext context) {
    _syncEpoch();
    if (_disposed ||
        _session.origin.isEmpty ||
        _scheduled ||
        _inflight != null ||
        _isComplete) {
      return false;
    }
    _scheduled = true;
    final epoch = _session.epoch;
    final generation = _generation;
    SchedulerBinding.instance.scheduleTask<void>(
      () {
        _scheduled = false;
        if (_isCurrent(epoch, generation) && context.mounted) {
          unawaited(warm(context));
        }
      },
      Priority.idle,
      debugLabel: 'Luma media branch prewarm',
    );
    return true;
  }

  /// 立即执行一次有界预热；单项失败不会阻止其他分支继续准备。
  Future<void> warm(BuildContext context) {
    _syncEpoch();
    final pending = _inflight;
    if (pending != null) return pending;
    if (_disposed || _session.origin.isEmpty || _isComplete) {
      return Future.value();
    }
    final epoch = _session.epoch;
    final generation = _generation;
    late final Future<void> request;
    request = _run(context, epoch, generation).whenComplete(() {
      if (identical(_inflight, request)) _inflight = null;
    });
    _inflight = request;
    return request;
  }

  /// 清除当前服务器的预热结果，并让尚未结束的旧任务失效。
  void reset() {
    if (_disposed) return;
    _generation++;
    _epoch = _session.epoch;
    _photos = const [];
    _catalogItems.clear();
    _catalogReady.clear();
    _photosReady = false;
    _inflight = null;
    _scheduled = false;
  }

  /// 停止发布预热结果；已经发出的网络请求可自然结束但会被忽略。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _photos = const [];
    _catalogItems.clear();
    _catalogReady.clear();
    _photosReady = false;
    _inflight = null;
  }

  bool get _isComplete =>
      _photosReady && _catalogReady.length == CatalogKind.values.length;

  Future<void> _run(
    BuildContext context,
    int epoch,
    int generation,
  ) async {
    try {
      final page = await _media.searchPage(
        const MediaFilter(type: MediaType.image),
        limit: 12,
      );
      if (!_isCurrent(epoch, generation)) return;
      if (!context.mounted) return;
      _photos = page.items;
      _photosReady = true;
      await _precachePhotos(context, page.items.take(3), epoch, generation);
    } on Object {
      // 空闲预热失败不改变页面加载和重试路径。
    }

    for (final kind in CatalogKind.values) {
      try {
        final items = await _catalog.list(kind: kind);
        if (!_isCurrent(epoch, generation)) return;
        if (!context.mounted) return;
        _catalogItems[kind] = items;
        _catalogReady.add(kind);
        if (kind == CatalogKind.movie) {
          await _precachePosters(
            context,
            items.take(3),
            epoch,
            generation,
          );
        }
      } on Object {
        // 单个影视分区失败时保留其他已经完成的预热结果。
      }
    }
  }

  Future<void> _precachePhotos(
    BuildContext context,
    Iterable<MediaItem> items,
    int epoch,
    int generation,
  ) async {
    if (!context.mounted) return;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final contentWidth = math.min(
      viewportWidth,
      LumaLayout.contentMaxWidth,
    );
    final gridWidth = math.max(1.0, contentWidth - LumaSpacing.md);
    final columns = LumaLayout.gridColumns(gridWidth);
    final tileWidth =
        (gridWidth - LumaSpacing.xs * (columns - 1)) / columns;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    for (final item in items) {
      if (!_isCurrent(epoch, generation) || !context.mounted) return;
      final ratio = (item.aspectRatio > 0.05 ? item.aspectRatio : 1.0).clamp(
        0.25,
        4.0,
      );
      final cacheWidth = (tileWidth * dpr).round().clamp(1, 640);
      final cacheHeight = (tileWidth / ratio * dpr).round().clamp(1, 1280);
      await _precachePath(
        context,
        item.thumbnailUrl,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        resizePolicy: ResizeImagePolicy.fit,
      );
    }
  }

  Future<void> _precachePosters(
    BuildContext context,
    Iterable<CatalogItem> items,
    int epoch,
    int generation,
  ) async {
    if (!context.mounted) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (138 * dpr).round().clamp(1, 640);
    for (final item in items) {
      if (!_isCurrent(epoch, generation) || !context.mounted) return;
      await _precachePath(
        context,
        item.posterUrl,
        cacheWidth: cacheWidth,
      );
    }
  }

  Future<void> _precachePath(
    BuildContext context,
    String path, {
    required int cacheWidth,
    int? cacheHeight,
    ResizeImagePolicy resizePolicy = ResizeImagePolicy.exact,
  }) async {
    if (path.isEmpty || !context.mounted) return;
    final access = _session.resolveResource(path);
    final provider = ResizeImage(
      NetworkImage(access.url, headers: access.headers),
      width: cacheWidth,
      height: cacheHeight,
      policy: resizePolicy,
    );
    await _precacheImage(provider, context);
  }

  bool _isCurrent(int epoch, int generation) =>
      !_disposed &&
      _session.epoch == epoch &&
      _generation == generation;

  void _syncEpoch() {
    if (_epoch == _session.epoch) return;
    _generation++;
    _epoch = _session.epoch;
    _photos = const [];
    _catalogItems.clear();
    _catalogReady.clear();
    _photosReady = false;
    _inflight = null;
    _scheduled = false;
  }

  static Future<void> _defaultPrecacheImage(
    ImageProvider<Object> provider,
    BuildContext context,
  ) => precacheImage(provider, context, onError: (_, _) {});
}
