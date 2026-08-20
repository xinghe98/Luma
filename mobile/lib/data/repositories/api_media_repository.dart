import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../decoders/media_decoder.dart';
import '../decoders/media_user_data_decoder.dart';
import '../decoders/tag_decoder.dart';
import '../models/api_media.dart';
import '../models/api_tag.dart';
import '../models/api_user_data.dart';
import '../models/media_filter.dart';
import '../models/media_item.dart';
import '../models/media_types.dart';
import 'media_repository.dart';
import 'source_repository.dart';

final class ApiMediaRepository
    implements MediaRepository, SessionResettableMediaRepository {
  ApiMediaRepository(this._client, this._sources);

  final ApiClient _client;
  final SourceRepository _sources;
  final MediaDecoder _mediaDecoder = const MediaDecoder();
  final MediaUserDataDecoder _userDataDecoder = const MediaUserDataDecoder();
  final TagDecoder _tagDecoder = const TagDecoder();
  final Map<String, MediaItem> _items = {};
  int? _cacheEpoch;

  static const _maxCachedItems = 512;

  /// 清除所有媒体缓存及其所属 epoch。
  @override
  void clearSessionCache() {
    _items.clear();
    _cacheEpoch = null;
  }

  @override
  Future<List<MediaItem>> loadMedia() =>
      _loadPages(maxPages: _homeMaxPages, replaceCache: true);

  @override
  Future<List<MediaItem>> refresh() =>
      _loadPages(maxPages: _homeMaxPages, replaceCache: true);

  /// 在单一会话 epoch 内拉完筛选结果，并缓存每页摘要。
  @override
  Future<List<MediaItem>> search(MediaFilter filter) async {
    // 兼容旧调用：连续拉完当前筛选（库页应改用 searchPage）。
    final epoch = _captureSessionEpoch();
    final items = <MediaItem>[];
    String? cursor;
    do {
      final page = await searchPage(filter, cursor: cursor);
      _client.ensureSessionEpoch(epoch);
      items.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor != null);
    return items;
  }

  /// 拉取一页筛选结果；会话切换后拒绝将旧响应写入缓存。
  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async {
    final epoch = _captureSessionEpoch();
    final page = _mediaDecoder.decodePage(
      await _client.getMedia(
        query: filter.text.trim().isEmpty ? null : filter.text.trim(),
        type: filter.type?.name,
        libraryKind: filter.libraryKind,
        favorite: filter.favoritesOnly ? true : null,
        tagId: filter.tagId,
        watchStatus: _watchStatus(filter.watchStatus),
        sort: switch (filter.sort) {
          MediaSort.title => 'filename',
          MediaSort.duration => 'duration',
          _ => 'created_at',
        },
        order: filter.sort == MediaSort.title ? 'asc' : 'desc',
        cursor: cursor,
        limit: limit ?? _pageSize,
      ),
    );
    _client.ensureSessionEpoch(epoch);
    final items = page.items.map(_rememberSummary).toList(growable: false);
    return MediaListPage(items: items, nextCursor: page.nextCursor);
  }

  @override
  Future<int> countMedia({MediaType? type}) async {
    final response = await _client.getMediaCount(type: type?.name);
    final raw = response['count'];
    if (raw is int && raw >= 0) return raw;
    if (raw is num && raw >= 0) return raw.toInt();
    throw const FormatException('媒体总数响应无效');
  }

  /// 加载继续观看摘要，并只缓存当前会话返回的条目。
  @override
  Future<List<MediaItem>> loadContinueWatching() async {
    // 首页只需少量继续观看项，单页足够。
    final epoch = _captureSessionEpoch();
    final page = _mediaDecoder.decodePage(
      await _client.getContinueWatching(limit: _pageSize),
    );
    _client.ensureSessionEpoch(epoch);
    return page.items.map(_rememberSummary).toList(growable: false);
  }

  @override
  Future<List<Tag>> loadTags() async =>
      _tagDecoder.decodeList(await _client.getTags());

  /// 并行加载媒体详情和用户数据，再解析来源并写入当前会话缓存。
  @override
  Future<MediaItem> loadDetail(String id) async {
    final epoch = _captureSessionEpoch();
    final responses = await Future.wait([
      _client.getMediaDetail(id),
      _client.getUserData(id),
    ]);
    final detail = _mediaDecoder.decodeDetail(responses[0]);
    final userData = _userDataDecoder.decode(responses[1]);
    final source = await _sources.find(detail.sourceId);
    _client.ensureSessionEpoch(epoch);
    return _remember(
      _fromDetail(detail, userData, source?.name ?? detail.sourceId),
    );
  }

  @override
  Future<MediaItem> setFavorite(String id, bool value) =>
      _updateUserData(id, {'favorite': value});

  @override
  Future<MediaItem> saveNote(String id, String note) =>
      _updateUserData(id, {'notes': note.isEmpty ? null : note});

  /// 上报绝对播放位置；冲突时仅在原会话内重取 revision 并重试一次。
  @override
  Future<MediaItem> updateProgress(String id, int positionMs) async {
    final epoch = _captureSessionEpoch();
    final item = _requiredItem(id);
    final safePosition = positionMs < 0 ? 0 : positionMs;
    Future<MediaUserData> send(int revision) async => _userDataDecoder.decode(
      await _client.updateProgress(
        mediaId: id,
        positionMs: safePosition,
        baseRevision: revision,
      ),
    );
    final data = await _withRevisionRetry(
      id,
      item.userDataRevision,
      epoch,
      send,
    );
    _client.ensureSessionEpoch(epoch);
    return _remember(_mergeUserData(item, data));
  }

  /// 单次请求条数。
  static const _pageSize = 48;

  /// 首页媒体摘要只拉前几页，完整浏览交给库页分页。
  static const _homeMaxPages = 2;

  // 首页/刷新用的有限分页拉取。
  Future<List<MediaItem>> _loadPages({
    bool replaceCache = true,
    int maxPages = _homeMaxPages,
  }) async {
    final epoch = _captureSessionEpoch();
    final summaries = <MediaSummary>[];
    String? cursor;
    var pages = 0;
    do {
      final page = _mediaDecoder.decodePage(
        await _client.getMedia(
          sort: 'created_at',
          order: 'desc',
          cursor: cursor,
          limit: _pageSize,
        ),
      );
      summaries.addAll(page.items);
      _client.ensureSessionEpoch(epoch);
      cursor = page.nextCursor;
      pages++;
    } while (cursor != null && pages < maxPages);

    final result = <MediaItem>[];
    if (replaceCache) {
      final next = <String, MediaItem>{};
      for (final summary in summaries) {
        final item = _mergeCachedUserData(
          _fromSummary(summary, _items[summary.id]),
          _items[summary.id],
        );
        next[item.id] = item;
        result.add(item);
      }
      // 保留已 remember 的详情缓存，避免首页刷新冲掉库页已打开的条目。
      for (final entry in _items.entries) {
        next.putIfAbsent(entry.key, () => entry.value);
      }
      _items
        ..clear()
        ..addAll(next);
      _trimCache();
    } else {
      for (final summary in summaries) {
        result.add(_rememberSummary(summary));
      }
    }
    return result;
  }

  Future<MediaItem> _updateUserData(
    String id,
    Map<String, dynamic> changes,
  ) async {
    final epoch = _captureSessionEpoch();
    final item = _requiredItem(id);
    Future<MediaUserData> send(int revision) async => _userDataDecoder.decode(
      await _client.updateUserData(id, {'base_revision': revision, ...changes}),
    );
    final data = await _withRevisionRetry(
      id,
      item.userDataRevision,
      epoch,
      send,
    );
    _client.ensureSessionEpoch(epoch);
    return _remember(_mergeUserData(item, data));
  }

  Future<MediaUserData> _withRevisionRetry(
    String id,
    int revision,
    int epoch,
    Future<MediaUserData> Function(int revision) request,
  ) async {
    try {
      return await request(revision);
    } on ApiException catch (error) {
      if (error.code != 'REVISION_CONFLICT') rethrow;
      _client.ensureSessionEpoch(epoch);
      final latest = _userDataDecoder.decode(await _client.getUserData(id));
      _client.ensureSessionEpoch(epoch);
      return request(latest.revision);
    }
  }

  MediaItem _rememberSummary(MediaSummary summary) {
    final item = _fromSummary(summary, _items[summary.id]);
    return _remember(item);
  }

  MediaItem _fromSummary(MediaSummary value, MediaItem? existing) {
    final duration = Duration(milliseconds: value.durationMs ?? 0);
    final width = value.width;
    final height = value.height;
    return MediaItem(
      id: value.id,
      title: value.title,
      type: value.mediaType,
      duration: duration,
      resolution: width == null || height == null ? '' : '$width×$height',
      format: _extension(value.filename),
      fileSize: existing?.fileSize ?? '',
      directory: existing?.directory ?? '',
      tags: existing?.tags ?? const [],
      addedAt: value.fileCreatedAt ?? value.createdAt,
      artSeed: value.id.hashCode.abs(),
      aspectRatio: width == null || height == null || height == 0
          ? 16 / 9
          : width / height,
      isFavorite: value.favorite,
      progress: duration.inMilliseconds == 0
          ? 0
          : value.progressMs / duration.inMilliseconds,
      note: existing?.note ?? '',
      filename: value.filename,
      thumbnailUrl: value.thumbnailUrl,
      cardThumbnailUrl: value.cardThumbnailUrl,
      streamUrl: value.streamUrl,
      originalUrl: value.originalUrl,
      mimeType: existing?.mimeType ?? '',
      sourceId: existing?.sourceId ?? '',
      libraryKind: value.libraryKind,
      catalogItemId: value.catalogItemId,
      videoCodec: existing?.videoCodec ?? '',
      audioCodec: existing?.audioCodec ?? '',
      bitrate: existing?.bitrate ?? 0,
      userDataRevision: value.userDataRevision,
      completed: value.completed,
      lastPlayedAt: value.lastPlayedAt,
      status: value.status,
    );
  }

  MediaItem _fromDetail(
    MediaDetail detail,
    MediaUserData data,
    String sourceName,
  ) {
    final base = _fromSummary(detail, _items[detail.id]);
    return _mergeUserData(
      base.copyWith(
        format: detail.container.isEmpty
            ? _extension(detail.filename)
            : detail.container,
        fileSize: _formatBytes(detail.fileSize),
        addedAt: detail.fileCreatedAt ?? detail.createdAt,
        mimeType: detail.mimeType,
        sourceId: detail.sourceId,
        sourceName: sourceName,
        videoCodec: detail.videoCodec,
        audioCodec: detail.audioCodec,
        bitrate: detail.bitrate,
      ),
      data,
    );
  }

  MediaItem _mergeUserData(MediaItem item, MediaUserData data) {
    final durationMs = item.duration.inMilliseconds;
    return item.copyWith(
      title: data.customTitle ?? item.title,
      tags: data.tags.map((tag) => tag.name).toList(growable: false),
      isFavorite: data.favorite,
      progress: durationMs == 0 ? 0 : data.progressMs / durationMs,
      note: data.notes ?? '',
      userDataRevision: data.revision,
      completed: data.completed,
      lastPlayedAt: data.lastPlayedAt,
      clearLastPlayedAt: data.lastPlayedAt == null && item.lastPlayedAt != null,
    );
  }

  MediaItem _remember(MediaItem item) {
    item = _mergeCachedUserData(item, _items[item.id]);
    _items.remove(item.id);
    _items[item.id] = item;
    _trimCache();
    return item;
  }

  /// 较旧响应可以更新媒体元数据，但不能覆盖缓存中 revision 更高的用户字段。
  MediaItem _mergeCachedUserData(MediaItem incoming, MediaItem? cached) {
    if (cached == null ||
        incoming.userDataRevision >= cached.userDataRevision) {
      return incoming;
    }
    return incoming.copyWith(
      tags: cached.tags,
      isFavorite: cached.isFavorite,
      progress: cached.progress,
      note: cached.note,
      userDataRevision: cached.userDataRevision,
      completed: cached.completed,
      lastPlayedAt: cached.lastPlayedAt,
      clearLastPlayedAt:
          cached.lastPlayedAt == null && incoming.lastPlayedAt != null,
    );
  }

  void _trimCache() {
    while (_items.length > _maxCachedItems) {
      _items.remove(_items.keys.first);
    }
  }

  MediaItem _requiredItem(String id) {
    _captureSessionEpoch();
    final item = _items[id];
    if (item == null) throw StateError('Unknown media: $id');
    return item;
  }

  static String _extension(String filename) {
    final index = filename.lastIndexOf('.');
    return index < 0 ? '' : filename.substring(index + 1).toUpperCase();
  }

  static String? _watchStatus(WatchStatus? status) => switch (status) {
    WatchStatus.unwatched => 'unwatched',
    WatchStatus.watching => 'watching',
    WatchStatus.watched => 'completed',
    null => null,
  };

  static String _formatBytes(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1048576) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  int _captureSessionEpoch() {
    final epoch = _client.captureSessionEpoch();
    if (_cacheEpoch != null && _cacheEpoch != epoch) _items.clear();
    _cacheEpoch = epoch;
    return epoch;
  }
}
