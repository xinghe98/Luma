// 验证选集按季集合并、清晰度只来自真实文件，以及刷新/选择的失败与过时回包。
// 使用内存仓储与真实选择控制器，解码和续播由播放器回归及原生冒烟覆盖。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_store.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/player/player_selection_controller.dart';

void main() {
  test('同集多个文件只产生一个选集项，清晰度来自该集的 episodes 行', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    expect(harness.selection.showEpisodes, isTrue);
    expect(harness.selection.episodes.map((e) => e.mediaId), [
      'special',
      'a',
      'b',
      'c',
    ]);
    expect(harness.selection.selectedEpisodeMediaId, 'a');
    expect(harness.selection.qualities.map((e) => e.mediaId), ['a', 'a4k']);
    expect(harness.selection.qualities.map((e) => e.label), ['1080p', '4K']);
    expect(await harness.selection.selectQuality('b'), isFalse);
    expect(harness.player.item.id, 'a');
    expect(harness.repository.detailCalls, isEmpty);
  });

  test('电影提供实际版本，独立媒体只提供当前文件且没有选集', () async {
    final harness = _Harness(catalog: _catalog(movie: true));
    addTearDown(harness.dispose);
    expect(harness.selection.showEpisodes, isFalse);
    expect(harness.selection.qualities.map((e) => e.mediaId), ['a', 'a4k']);
    expect(harness.selection.qualities.last.description, contains('HEVC'));
    final personal = _Harness(
      item: _item('personal', catalogId: null),
      cached: false,
    );
    addTearDown(personal.dispose);
    expect(personal.selection.showEpisodes, isFalse);
    expect(personal.selection.qualities.single.mediaId, 'personal');
    expect(await personal.selection.selectQuality('personal'), isTrue);
    expect(personal.repository.detailCalls, isEmpty);
  });

  test('加载失败的目标不会更换当前文件，旧选项仍可选择', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.fail = true;
    expect(await harness.selection.selectEpisode('b'), isFalse);
    expect(harness.player.item.id, 'a');
    expect(harness.selection.error, isNotNull);
    expect(harness.selection.switching, isFalse);
    expect(harness.selection.episodes.map((e) => e.mediaId), contains('b'));
  });

  test('销毁选择器后，迟到的媒体详情不能启动新集', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final gate = Completer<MediaItem>();
    harness.repository.gate = gate;
    final pending = harness.selection.selectEpisode('b');
    expect(harness.selection.switching, isTrue);
    harness.selection.dispose();
    gate.complete(_item('b'));
    expect(await pending, isFalse);
    expect(harness.player.item.id, 'a');
  });

  test('刷新失败保留缓存，重试清除错误并接受相同时间戳的新详情', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.catalogRepository.fail = true;
    await harness.selection.refresh();
    expect(harness.selection.loading, isFalse);
    expect(harness.selection.error, isNotNull);
    expect(harness.selection.qualities.map((e) => e.mediaId), ['a', 'a4k']);
    harness.catalogRepository
      ..fail = false
      ..item = _catalog(extraVersion: true);
    await harness.selection.refresh();
    expect(harness.selection.error, isNull);
    expect(harness.selection.qualities.map((e) => e.mediaId), [
      'a',
      'a4k',
      'a720',
    ]);
  });

  test('电视剧深链加载前保留选集入口，详情补全归属后展示全部选项', () async {
    final harness = _Harness(
      item: _item('a', catalogId: null, television: true),
      cached: false,
    );
    addTearDown(harness.dispose);
    expect(harness.selection.showEpisodes, isTrue);
    expect(harness.selection.episodes, isEmpty);
    await harness.selection.refresh();
    expect(harness.selection.loading, isFalse);
    expect(harness.selection.episodes.map((e) => e.mediaId), [
      'special',
      'a',
      'b',
      'c',
    ]);
  });

  test('后台旧作品刷新结束不会覆盖新的播放文件选项', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final gate = Completer<CatalogItem>();
    harness.catalogRepository.gate = gate;
    final pending = harness.selection.refresh();
    harness.player.setItemForTest(_item('personal', catalogId: null));
    gate.complete(_catalog());
    await pending;
    expect(harness.selection.loading, isFalse);
    expect(harness.selection.showEpisodes, isFalse);
    expect(harness.selection.qualities.single.mediaId, 'personal');
  });
}

class _Harness {
  _Harness({MediaItem? item, CatalogItem? catalog, bool cached = true}) {
    final initial = item ?? _item('a');
    catalogRepository = _CatalogRepository(catalog ?? _catalog());
    store = CatalogStore(catalogRepository);
    if (cached) store.rememberAll([catalogRepository.item], notify: false);
    player = _MutablePlayer(item: initial, media: media);
    selection = PlayerSelectionController(
      player: player,
      media: media,
      catalog: store,
    );
  }
  final repository = _MediaRepository();
  late final media = MediaController(repository);
  late final _CatalogRepository catalogRepository;
  late final CatalogStore store;
  late final _MutablePlayer player;
  late final PlayerSelectionController selection;
  void dispose() {
    selection.dispose();
    player.dispose();
    store.dispose();
    media.dispose();
  }
}

class _MutablePlayer extends PlayerController {
  _MutablePlayer({required super.item, required super.media});
  MediaItem? _current;
  @override
  MediaItem get item => _current ?? super.item;
  void setItemForTest(MediaItem item) {
    _current = item;
    notifyListeners();
  }
}

class _MediaRepository extends MockMediaRepository {
  bool fail = false;
  Completer<MediaItem>? gate;
  final List<String> detailCalls = [];
  @override
  Future<MediaItem> loadDetail(String id) async {
    detailCalls.add(id);
    if (fail) throw StateError('媒体读取失败');
    return gate != null ? await gate!.future : _item(id);
  }
}

class _CatalogRepository implements CatalogRepository {
  _CatalogRepository(this.item);
  CatalogItem item;
  bool fail = false;
  Completer<CatalogItem>? gate;
  @override
  Future<CatalogItem> detail(String id) async {
    if (fail) throw StateError('作品读取失败');
    return gate != null ? await gate!.future : item;
  }

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async => [
    item,
  ];
  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async => CatalogFavorite(favorite: favorite, revision: revision + 1);
}

MediaItem _item(
  String id, {
  String? catalogId = 'series',
  bool television = false,
}) => MediaItem(
  id: id,
  title: id,
  type: MediaType.video,
  duration: const Duration(minutes: 30),
  resolution: '1080p',
  format: 'MP4',
  fileSize: '1 GB',
  directory: '',
  tags: const [],
  addedAt: DateTime(2026),
  artSeed: 0,
  catalogItemId: catalogId,
  libraryKind: television ? 'tv' : 'personal',
  streamUrl: 'http://127.0.0.1/stream/$id',
);

CatalogEpisode _episode(
  String id,
  int season,
  int episode, {
  String resolution = '1080p',
}) => CatalogEpisode(
  id: id,
  seasonNumber: season,
  episodeNumber: episode,
  title: id,
  mediaId: id,
  durationMs: 1800000,
  resolution: resolution,
  progressMs: 0,
  completed: false,
  thumbnailUrl: '',
);

CatalogItem _catalog({bool movie = false, bool extraVersion = false}) =>
    CatalogItem(
      id: 'series',
      sourceId: 'source',
      kind: movie ? CatalogKind.movie : CatalogKind.series,
      title: '作品',
      year: 2026,
      mediaCount: 5,
      episodeCount: 4,
      completedCount: 0,
      playableMediaId: 'a',
      thumbnailUrl: '',
      posterUrl: '',
      durationMs: 1800000,
      resolution: '1080p',
      progressMs: 0,
      completed: false,
      updatedAt: DateTime(2026),
      episodes: movie
          ? const []
          : [
              _episode('b', 1, 2),
              _episode('c', 2, 1),
              _episode('a', 1, 1),
              _episode('a4k', 1, 1, resolution: '4K'),
              _episode('special', 0, 1),
              if (extraVersion) _episode('a720', 1, 1, resolution: '720p'),
            ],
      versions: !movie
          ? const []
          : [
              for (final id in ['a', 'a4k'])
                CatalogVersion(
                  mediaId: id,
                  label: id == 'a' ? '原版' : '高码率',
                  fileSize: 1024,
                  durationMs: 1800000,
                  resolution: id == 'a' ? '1080p' : '4K',
                  videoCodec: id == 'a' ? 'H264' : 'HEVC',
                  audioCodec: 'AAC',
                  audioTrackCount: 1,
                  progressMs: 0,
                  completed: false,
                  selected: id == 'a',
                ),
            ],
    );
