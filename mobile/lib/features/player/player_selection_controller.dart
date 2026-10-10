// 播放页选择状态：从 CatalogStore 的剧集/电影版本生成选项，交给播放器切换文件。
// 页面负责创建、刷新和销毁；播放器的位置通知不重建选项，过时请求不会切换媒体。
import 'package:flutter/foundation.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/models/api_catalog.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import '../catalog/catalog_store.dart';
import 'player_controller.dart';

/// 一个实际媒体文件或剧集代表项，不包含服务端未提供的转码档位。
@immutable
class PlayerMediaChoice {
  /// 用媒体 ID 标识选择，描述用于区分季、集或同清晰度的文件版本。
  const PlayerMediaChoice({
    required this.mediaId,
    required this.label,
    this.description,
  });
  final String mediaId;
  final String label;
  final String? description;
}

/// 管理当前播放文件的选集、清晰度及加载错误，生命周期由播放页持有。
class PlayerSelectionController extends ChangeNotifier {
  /// 立即读取已有作品快照并监听身份变化；网络刷新由页面显式触发。
  PlayerSelectionController({
    required PlayerController player,
    required MediaController media,
    required CatalogStore catalog,
  }) : _player = player,
       _media = media,
       _catalog = catalog {
    _player.addListener(_handleChanged);
    _media.addListener(_handleChanged);
    _catalog.addListener(_handleChanged);
    _recompute();
  }

  final PlayerController _player;
  final MediaController _media;
  final CatalogStore _catalog;
  MediaItem? _snapshotItem;
  CatalogItem? _snapshotCatalog;
  String? _catalogId;
  List<PlayerMediaChoice> _episodes = const [];
  List<PlayerMediaChoice> _qualities = const [];
  String? _selectedEpisodeMediaId;
  bool _loading = false;
  bool _switching = false;
  bool _disposed = false;
  String? _error;
  int _refreshGeneration = 0;

  /// 电视剧即使尚未加载或加载失败也保留入口，面板提供重试。
  bool get showEpisodes =>
      _snapshotCatalog?.kind == CatalogKind.series ||
      _player.item.libraryKind == 'tv';
  bool get loading => _loading;
  bool get switching => _switching;
  String? get error => _error;
  List<PlayerMediaChoice> get episodes => _episodes;
  List<PlayerMediaChoice> get qualities => _qualities;
  String? get selectedEpisodeMediaId => _selectedEpisodeMediaId;
  String get selectedQualityMediaId => _player.item.id;

  /// 刷新所属作品；必要时先补全深链媒体归属，失败保留旧选项并允许重试。
  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_refreshGeneration;
    final item = _player.item;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (_catalogId == null &&
          (item.libraryKind == 'movies' || item.libraryKind == 'tv')) {
        await _media.loadDetail(item.id);
        if (!_isCurrentRefresh(generation, item.id)) return;
        if (_media.detailError != null) {
          _error = _media.detailError;
          return;
        }
        _recompute();
      }
      final catalogId = _catalogId;
      if (catalogId != null) await _catalog.detail(catalogId);
    } on Object catch (error) {
      if (_isCurrentRefresh(generation, item.id)) _error = error.toString();
    } finally {
      if (_isCurrentRefresh(generation, item.id)) {
        _loading = false;
        _recompute();
        notifyListeners();
      }
    }
  }

  /// 切换到所选集的代表文件，使用目标集自己的续播进度；校验失败保留旧播放。
  Future<bool> selectEpisode(String mediaId) =>
      _select(mediaId, preservePosition: false);

  /// 切换当前集或电影的实际文件版本，保留加载完成时的播放时间与暂停状态。
  Future<bool> selectQuality(String mediaId) =>
      _select(mediaId, preservePosition: true);

  Future<bool> _select(String mediaId, {required bool preservePosition}) async {
    if (_disposed || _switching) return false;
    final choices = preservePosition ? _qualities : _episodes;
    if (!choices.any((choice) => choice.mediaId == mediaId)) return false;
    if (mediaId == _player.item.id) return true;
    final previousId = _player.item.id;
    _switching = true;
    _error = null;
    notifyListeners();
    try {
      await _media.loadDetail(mediaId);
      if (_disposed || _player.item.id != previousId) return false;
      if (_media.detailError != null) {
        _error = _media.detailError;
        return false;
      }
      final next = _media.findById(mediaId);
      if (next == null ||
          next.type != MediaType.video ||
          next.status != 'ready' ||
          (next.streamUrl?.isEmpty ?? true)) {
        _error = '所选文件暂不可播放';
        return false;
      }
      await _player.replaceMedia(
        (next.catalogItemId?.isNotEmpty ?? false)
            ? next
            : next.copyWith(catalogItemId: _catalogId),
        resumePosition: preservePosition ? _player.position : null,
        preservePause: preservePosition,
      );
      // 解码错误由播放器自身的重试入口处理，面板不遮挡新文件的失败状态。
      return !_disposed && _player.item.id == mediaId;
    } on Object catch (error) {
      if (!_disposed && _player.item.id == previousId) {
        _error = error.toString();
      }
      return false;
    } finally {
      if (!_disposed) {
        _switching = false;
        _recompute();
        notifyListeners();
      }
    }
  }

  bool _isCurrentRefresh(int generation, String mediaId) =>
      !_disposed &&
      generation == _refreshGeneration &&
      _player.item.id == mediaId;

  String? _associatedCatalogId(MediaItem item) {
    final id = item.catalogItemId;
    if (id != null && id.isNotEmpty) return id;
    final cached = _media.findById(item.id)?.catalogItemId;
    return cached == null || cached.isEmpty ? null : cached;
  }

  /// 按对象身份判断是否需要重算，播放位置变化不分配缓存键或新列表。
  void _handleChanged() {
    if (_disposed) return;
    final item = _player.item;
    final catalogId = _associatedCatalogId(item);
    final catalog = catalogId == null ? null : _catalog.findById(catalogId);
    if (identical(item, _snapshotItem) &&
        catalogId == _catalogId &&
        identical(catalog, _snapshotCatalog)) {
      return;
    }
    if (_snapshotItem?.id != item.id) {
      _refreshGeneration++;
      _loading = false;
    }
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    final item = _player.item;
    _snapshotItem = item;
    _catalogId = _associatedCatalogId(item);
    final id = _catalogId;
    final catalog = id == null ? null : _catalog.findById(id);
    _snapshotCatalog = catalog;
    _selectedEpisodeMediaId = null;
    _episodes = const [];
    if (item.type != MediaType.video) {
      _qualities = const [];
      return;
    }
    _qualities = [_currentChoice(item)];
    if (catalog == null) return;
    if (catalog.kind == CatalogKind.movie) {
      final seen = <String>{};
      final choices = <PlayerMediaChoice>[];
      for (final version in catalog.versions) {
        if (version.mediaId.isEmpty || !seen.add(version.mediaId)) continue;
        final parts = [
          if (version.label.isNotEmpty && version.label != version.resolution)
            version.label,
          if (version.videoCodec.isNotEmpty) version.videoCodec,
          if (version.audioTrackCount > 1) '${version.audioTrackCount} 音轨',
        ];
        choices.add(
          PlayerMediaChoice(
            mediaId: version.mediaId,
            label: version.resolution.isEmpty ? '原画' : version.resolution,
            description: parts.isEmpty ? null : parts.join(' · '),
          ),
        );
      }
      if (seen.add(item.id)) choices.add(_currentChoice(item));
      _qualities = _withSingleVersionHint(choices);
      return;
    }
    final groups = <(int, int), List<CatalogEpisode>>{};
    for (final episode in catalog.episodes) {
      if (episode.mediaId.isEmpty) continue;
      (groups[(episode.seasonNumber, episode.episodeNumber)] ??= []).add(
        episode,
      );
    }
    final sorted = groups.keys.toList()
      ..sort((a, b) {
        final season = a.$1.compareTo(b.$1);
        return season == 0 ? a.$2.compareTo(b.$2) : season;
      });
    final episodes = <PlayerMediaChoice>[];
    for (final key in sorted) {
      final group = groups[key]!;
      var representative = group.first;
      var containsCurrent = false;
      for (final episode in group) {
        if (episode.resolution == item.resolution) representative = episode;
        if (episode.mediaId == item.id) {
          representative = episode;
          containsCurrent = true;
          break;
        }
      }
      final season = key.$1 == 0 ? '特别篇' : '第 ${key.$1} 季';
      final label = '$season · 第 ${key.$2} 集';
      episodes.add(
        PlayerMediaChoice(
          mediaId: representative.mediaId,
          label: label,
          description: representative.title.isEmpty
              ? null
              : representative.title,
        ),
      );
      if (!containsCurrent) continue;
      _selectedEpisodeMediaId = item.id;
      final seen = <String>{};
      final choices = <PlayerMediaChoice>[];
      for (final episode in group) {
        if (!seen.add(episode.mediaId)) continue;
        choices.add(
          PlayerMediaChoice(
            mediaId: episode.mediaId,
            label: episode.resolution.isEmpty ? '原画' : episode.resolution,
            description: group.length > 1
                ? '$label · 版本 ${choices.length + 1}'
                : null,
          ),
        );
      }
      _qualities = _withSingleVersionHint(choices);
    }
    _episodes = List.unmodifiable(episodes);
  }

  List<PlayerMediaChoice> _withSingleVersionHint(
    List<PlayerMediaChoice> choices,
  ) {
    if (choices.length == 1) {
      final choice = choices.single;
      choices[0] = PlayerMediaChoice(
        mediaId: choice.mediaId,
        label: choice.label,
        description: [
          if (choice.description != null && choice.description != '仅此版本')
            choice.description!,
          '仅此版本',
        ].join(' · '),
      );
    }
    return List.unmodifiable(choices);
  }

  PlayerMediaChoice _currentChoice(MediaItem item) => PlayerMediaChoice(
    mediaId: item.id,
    label: item.resolution.isEmpty ? '原画' : item.resolution,
    description: '仅此版本',
  );

  /// 解除监听并使在途刷新、选择失效；不会停止页面之外持有的播放会话。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _refreshGeneration++;
    _player.removeListener(_handleChanged);
    _media.removeListener(_handleChanged);
    _catalog.removeListener(_handleChanged);
    super.dispose();
  }
}
