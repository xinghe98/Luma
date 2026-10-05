// TV 冒烟测试仓储：内存版媒体/作品数据与测试连接服务。
// 责任：提供 60 项媒体与作品/选集数据；进度更新返回更新后的模型并记录保存值。
// 生命周期：每个测试构造一次，随 AppDependencies 注入；不访问真实网络，
// 唯一的连接副作用是把 loopback origin 与固定 token 写入真实 ApiSession。
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/api_tag.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/data/repositories/media_repository.dart';
import 'package:luma/data/services/connection_service.dart';

import 'tv_smoke_server.dart';

/// 媒体标题中的搜索池关键字：搜索分支用它取回 24 条分页结果。
const String kTvSmokeSearchTerm = '夜行';

/// 首个可播放视频的媒体 id：浏览/详情/播放分支共用。
const String kTvSmokePlayTargetId = 'video-0';

/// 图片分支使用第一个图片条目的 id。
const String kTvSmokeImageTargetId = 'image-0';

/// 生成 60 项媒体：24 条搜索池视频、16 条普通视频、20 张图片。
/// 全部条目的缩略图与可播放地址都指向测试服务器（相对路径由 ApiSession 解析）。
List<MediaItem> buildTvSmokeMediaItems() {
  final now = DateTime(2026, 10, 1, 12);
  final items = <MediaItem>[];
  for (var i = 0; i < 24; i++) {
    items.add(
      MediaItem(
        id: 'video-$i',
        title: '$kTvSmokeSearchTerm快车 $i',
        type: MediaType.video,
        // 与测试视频一致的 30 秒时长，保证进度换算和原生时长对齐。
        duration: const Duration(seconds: 30),
        resolution: '1080p',
        format: 'MP4',
        fileSize: '0.3 MB',
        directory: '/tv-smoke/夜行',
        tags: const ['测试'],
        addedAt: now.subtract(Duration(minutes: i)),
        artSeed: i,
        progress: i == 0 ? 0.28 : (i % 5 == 0 ? 0.4 : 0.0),
        thumbnailUrl: tvSmokeImagePath('asset-${i % 8}'),
        cardThumbnailUrl: tvSmokeImagePath('asset-${i % 8}'),
        streamUrl: tvSmokeStreamPath('video-$i'),
        mimeType: 'video/mp4',
        sourceId: 'tv-smoke',
        sourceName: '烟测媒体源',
        libraryKind: 'personal',
        videoCodec: 'h264',
        audioCodec: 'aac',
        status: 'ready',
      ),
    );
  }
  for (var i = 0; i < 16; i++) {
    items.add(
      MediaItem(
        id: 'video-${24 + i}',
        title: '周末影像 $i',
        type: MediaType.video,
        duration: const Duration(seconds: 30),
        resolution: '720p',
        format: 'MP4',
        fileSize: '0.3 MB',
        directory: '/tv-smoke/周末',
        tags: const ['测试'],
        addedAt: now.subtract(Duration(hours: 2 + i)),
        artSeed: 24 + i,
        isFavorite: i < 3,
        thumbnailUrl: tvSmokeImagePath('asset-${(i + 3) % 8}'),
        streamUrl: tvSmokeStreamPath('video-${24 + i}'),
        mimeType: 'video/mp4',
        sourceId: 'tv-smoke',
        libraryKind: 'personal',
        status: 'ready',
      ),
    );
  }
  for (var i = 0; i < 20; i++) {
    items.add(
      MediaItem(
        id: 'image-$i',
        title: '相册风景 $i',
        type: MediaType.image,
        duration: Duration.zero,
        resolution: '96x64',
        format: 'PNG',
        fileSize: '0.5 KB',
        directory: '/tv-smoke/相册',
        tags: const ['测试'],
        addedAt: now.subtract(Duration(days: 1 + i)),
        artSeed: 40 + i,
        aspectRatio: 3 / 2,
        thumbnailUrl: tvSmokeImagePath('asset-$i'),
        originalUrl: tvSmokeImagePath('asset-$i'),
        sourceId: 'tv-smoke',
        libraryKind: 'personal',
      ),
    );
  }
  return items;
}

/// 内存媒体仓储：实现 MediaRepository 全部接口并记录写操作供断言。
final class TvSmokeMediaRepository implements MediaRepository {
  TvSmokeMediaRepository() : _items = buildTvSmokeMediaItems();

  List<MediaItem> _items;

  /// 每次进度保存的最新毫秒值；播放器退出后断言其非零。
  final Map<String, int> lastProgress = {};

  /// updateProgress 调用次数；用于确认暂停/退出确实触发保存。
  int updateProgressCalls = 0;

  /// searchPage 调用次数；第二次出现即代表搜索分页已触发。
  int searchPageCalls = 0;

  /// refresh 调用次数；首页刷新按钮应使它从初始加载的 1 再增加。
  int refreshCalls = 0;

  /// warmStream 调用次数。
  int warmCalls = 0;

  int _revision = 0;

  @override
  Future<List<MediaItem>> loadMedia() async => List.of(_items);

  @override
  Future<List<MediaItem>> refresh() async {
    refreshCalls++;
    return List.of(_items);
  }

  @override
  Future<List<MediaItem>> search(MediaFilter filter) async =>
      _filtered(filter).toList(growable: false);

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async {
    searchPageCalls++;
    final pageSize = limit ?? 12;
    final offset = cursor == null ? 0 : (int.tryParse(cursor) ?? 0);
    final all = _filtered(filter).toList(growable: false);
    final end = (offset + pageSize).clamp(0, all.length);
    final nextCursor = end < all.length ? '$end' : null;
    return MediaListPage(
      items: all.sublist(offset.clamp(0, all.length), end),
      nextCursor: nextCursor,
    );
  }

  @override
  Future<int> countMedia({MediaType? type}) async => type == null
      ? _items.length
      : _items.where((item) => item.type == type).length;

  @override
  Future<List<MediaItem>> loadContinueWatching() async => _items
      .where((item) => item.watchStatus == WatchStatus.watching)
      .toList(growable: false);

  @override
  Future<List<Tag>> loadTags() async => const [];

  @override
  Future<MediaItem> loadDetail(String id) async =>
      _items.firstWhere((item) => item.id == id);

  @override
  Future<void> warmStream(String id) async {
    warmCalls++;
  }

  @override
  Future<MediaItem> setFavorite(String id, bool value) =>
      _replace(id, (item) => item.copyWith(isFavorite: value));

  @override
  Future<MediaItem> saveNote(String id, String note) =>
      _replace(id, (item) => item.copyWith(note: note));

  @override
  Future<MediaItem> updateProgress(String id, int positionMs) =>
      _replace(id, (item) {
        lastProgress[id] = positionMs;
        updateProgressCalls++;
        final total = item.duration.inMilliseconds;
        final ratio = total <= 0 ? 0.0 : positionMs / total;
        return item.copyWith(
          progress: ratio.clamp(0.0, 1.0),
          completed: positionMs >= (total * 0.9).round() && total > 0,
          lastPlayedAt: DateTime.now(),
          userDataRevision: ++_revision,
        );
      });

  /// 按条件过滤并按加入时间倒序（MediaSort.newest 语义）。
  Iterable<MediaItem> _filtered(MediaFilter filter) {
    return _items.where((item) {
      if (filter.type != null && item.type != filter.type) return false;
      if (filter.libraryKind != null &&
          item.libraryKind != filter.libraryKind) {
        return false;
      }
      if (filter.favoritesOnly && !item.isFavorite) return false;
      if (filter.text.isNotEmpty && !item.title.contains(filter.text)) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Future<MediaItem> _replace(
    String id,
    MediaItem Function(MediaItem item) update,
  ) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('媒体不存在：$id');
    final updated = update(_items[index]);
    _items = List.of(_items)..[index] = updated;
    return updated;
  }
}

/// 内存作品仓储：8 部电影（带版本）+ 6 部剧集（各 3 集）。
/// 详情返回完整选集；收藏保存按条目内递增 revision 返回。
final class TvSmokeCatalogRepository implements CatalogRepository {
  TvSmokeCatalogRepository() {
    final now = DateTime(2026, 10, 1, 12);
    for (var i = 0; i < 8; i++) {
      final mediaId = 'video-${24 + (i % 16)}';
      _items['movie-$i'] = CatalogItem(
        id: 'movie-$i',
        sourceId: 'tv-smoke',
        kind: CatalogKind.movie,
        title: '午夜影院 $i',
        year: 2020 + i,
        mediaCount: 1,
        episodeCount: 0,
        completedCount: 0,
        playableMediaId: mediaId,
        thumbnailUrl: tvSmokeImagePath('asset-${i % 8}'),
        posterUrl: tvSmokeImagePath('asset-${i % 8}'),
        durationMs: 30000,
        resolution: '720p',
        progressMs: 0,
        completed: false,
        updatedAt: now.subtract(Duration(hours: i)),
        overview: '冒烟测试电影 $i 简介。',
        genres: const [CatalogNamedValue(id: 'g1', name: '测试')],
        versions: [
          CatalogVersion(
            mediaId: mediaId,
            label: '1080p 主版本',
            fileSize: 1,
            durationMs: 30000,
            resolution: '1080p',
            videoCodec: 'h264',
            audioCodec: 'aac',
            audioTrackCount: 1,
            progressMs: 0,
            completed: false,
            selected: true,
          ),
        ],
      );
    }
    for (var s = 0; s < 6; s++) {
      final episodes = List.generate(3, (e) {
        final mediaId = 'video-${24 + ((s * 3 + e) % 16)}';
        return CatalogEpisode(
          id: 'ep-$s-$e',
          seasonNumber: 1,
          episodeNumber: e + 1,
          title: '夜航日志 第${e + 1}集',
          mediaId: mediaId,
          durationMs: 30000,
          resolution: '1080p',
          progressMs: 0,
          completed: false,
          thumbnailUrl: tvSmokeImagePath('asset-${(s + e) % 8}'),
        );
      });
      _items['series-$s'] = CatalogItem(
        id: 'series-$s',
        sourceId: 'tv-smoke',
        kind: CatalogKind.series,
        title: '长夜剧场 $s',
        year: 2024,
        mediaCount: 3,
        episodeCount: 3,
        completedCount: 0,
        playableMediaId: episodes.first.mediaId,
        thumbnailUrl: tvSmokeImagePath('asset-${s % 8}'),
        posterUrl: tvSmokeImagePath('asset-${s % 8}'),
        durationMs: 90000,
        resolution: '1080p',
        progressMs: 0,
        completed: false,
        updatedAt: now.subtract(Duration(minutes: s)),
        overview: '冒烟测试剧集 $s 简介。',
        episodes: episodes,
      );
    }
  }

  final Map<String, CatalogItem> _items = {};

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async {
    return _items.values
        .where((item) {
          if (kind != null && item.kind != kind) return false;
          if (query != null &&
              query.isNotEmpty &&
              !item.title.contains(query)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  Future<CatalogItem> detail(String id) async {
    final item = _items[id];
    if (item == null) throw StateError('作品不存在：$id');
    return item;
  }

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async {
    final item = _items[catalogId];
    if (item == null) throw StateError('作品不存在：$catalogId');
    if (item.favoriteRevision != revision) {
      throw StateError('收藏版本冲突：期望 $revision，实际 ${item.favoriteRevision}');
    }
    final updated = CatalogItem(
      id: item.id,
      sourceId: item.sourceId,
      kind: item.kind,
      title: item.title,
      year: item.year,
      mediaCount: item.mediaCount,
      episodeCount: item.episodeCount,
      completedCount: item.completedCount,
      playableMediaId: item.playableMediaId,
      thumbnailUrl: item.thumbnailUrl,
      posterUrl: item.posterUrl,
      durationMs: item.durationMs,
      resolution: item.resolution,
      progressMs: item.progressMs,
      completed: item.completed,
      updatedAt: item.updatedAt,
      episodes: item.episodes,
      overview: item.overview,
      genres: item.genres,
      versions: item.versions,
      favorite: favorite,
      favoriteRevision: revision + 1,
    );
    _items[catalogId] = updated;
    return CatalogFavorite(favorite: favorite, revision: revision + 1);
  }
}

/// 测试连接服务：成功登录即把 loopback origin 与固定 token 写入真实 ApiSession，
/// 并发布可断言的 ServerProfile；不读写任何持久化凭据。
final class TvSmokeConnectionService implements ConnectionService {
  TvSmokeConnectionService(this._apiSession);

  final ApiSession _apiSession;

  /// disconnect 调用次数；断开分支断言至少一次。
  int disconnectCalls = 0;

  @override
  ServerProfile? connectedProfile;

  @override
  Future<ConnectionResult> login(
    String address,
    LoginCredentials credentials,
  ) async {
    final uri = Uri.tryParse(address.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return ConnectionResult.invalidAddress;
    }
    if (credentials.username.trim().isEmpty || credentials.password.isEmpty) {
      return ConnectionResult.unauthorized;
    }
    return _activate(address.trim());
  }

  @override
  Future<ConnectionResult> restore(String address, String sessionToken) async {
    final uri = Uri.tryParse(address.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return ConnectionResult.invalidAddress;
    }
    return _activate(address.trim());
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    connectedProfile = null;
    _apiSession.clear();
  }

  ConnectionResult _activate(String origin) {
    final normalized = origin.replaceFirst(RegExp(r'/+$'), '');
    _apiSession.update(origin: normalized, token: kTvSmokeToken);
    connectedProfile = ServerProfile(
      name: '烟测服务器',
      address: normalized,
      token: kTvSmokeToken,
      hostName: Uri.parse(normalized).host,
      sourceCount: 1,
      version: 'smoke-1.0',
      userRole: 'admin',
      capabilities: const ['scans.manage'],
    );
    return ConnectionResult.success;
  }
}
