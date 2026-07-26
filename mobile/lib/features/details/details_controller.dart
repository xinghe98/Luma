import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/models/media_item.dart';

class DetailsController extends ChangeNotifier {
  /// 绑定媒体详情状态；页面可关闭自动加载，并在路由过渡完成后主动刷新。
  DetailsController({
    required this.mediaId,
    required this.media,
    this.loadImmediately = true,
    this.showCachedBeforeInitialLoad = true,
  }) {
    media.addListener(notifyListeners);
    if (loadImmediately) unawaited(reload());
  }

  final String mediaId;
  final MediaController media;
  final bool loadImmediately;

  /// 为 false 时，即使全局缓存有摘要，也要等首次详情请求结束后再展示。
  final bool showCachedBeforeInitialLoad;
  bool _disposed = false;
  bool _initialLoadFinished = false;

  MediaItem? get item => !_initialLoadFinished && !showCachedBeforeInitialLoad
      ? null
      : media.findById(mediaId);
  String? get detailError => media.detailError;
  bool get isLoading =>
      item == null && (!_initialLoadFinished || media.detailLoading);
  bool get isMissing =>
      item == null && _initialLoadFinished && !media.detailLoading;

  /// 重新读取详情；失败信息由媒体控制器保留，已有条目不会被清除。
  Future<void> reload() async {
    if (_disposed) return;
    try {
      await media.loadDetail(mediaId);
    } finally {
      if (!_disposed) {
        _initialLoadFinished = true;
        notifyListeners();
      }
    }
  }

  Future<void> toggleFavorite() => media.toggleFavorite(mediaId);
  Future<void> saveNote(String note) => media.saveNote(mediaId, note);

  @override
  void dispose() {
    _disposed = true;
    media.removeListener(notifyListeners);
    super.dispose();
  }
}
