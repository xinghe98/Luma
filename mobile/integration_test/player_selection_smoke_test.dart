// 隔离验证播放器选集和清晰度切换；使用内存作品、本机鉴权服务与真实 libmpv。
// 复用正式选择面板和播放控制器，退出测试时卸下纹理并关闭中继及 HTTP 端口。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/proxy/loopback_media_relay.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_store.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/player/player_device_controls.dart';
import 'package:luma/features/player/player_interaction_controller.dart';
import 'package:luma/features/player/player_selection_controller.dart';
import 'package:luma/features/player/widgets/player_scene.dart';
import 'package:media_kit/media_kit.dart';

import 'fixtures/tv_smoke_clip.dart';
import 'support/tv_smoke_repositories.dart';
import 'support/tv_smoke_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实播放中切清晰度保留暂停与时间，选集恢复目标进度', (tester) async {
    MediaKit.ensureInitialized();
    final server = TvSmokeServer(videoBytes: tvSmokeClipBytes, imageCount: 0);
    final session = ApiSession();
    final relay = LoopbackMediaRelay(
      createHttpClient: () => HttpClient()..findProxy = (_) => 'DIRECT',
      authorizationHeadersFor: session.authorizationHeadersFor,
    );
    final repository = _SelectionMediaRepository();
    final media = MediaController(repository);
    final catalog = CatalogStore(_SelectionCatalogRepository(repository));
    final player = PlayerController(
      item: repository.items['video-0']!,
      media: media,
      apiSession: session,
      mediaRequestRouter: relay,
    );
    final selection = PlayerSelectionController(
      player: player,
      media: media,
      catalog: catalog,
    );
    final interaction = PlayerInteractionController(
      player: player,
      deviceControls: const MethodChannelPlayerDeviceControls(),
    );
    final surfaceKey = GlobalKey();
    try {
      await server.start();
      await relay.start();
      session.update(origin: server.origin, token: kTvSmokeToken);
      await selection.refresh();
      await tester.pumpWidget(
        RepaintBoundary(
          key: surfaceKey,
          child: MaterialApp(
            theme: LumaTheme.dark(),
            home: Scaffold(
              body: PlayerScene(
                controller: player,
                interaction: interaction,
                selection: selection,
                isDesktop: true,
                onBack: () {},
                onRotate: null,
              ),
            ),
          ),
        ),
      );
      player.start();
      await _pumpUntil(
        tester,
        () => player.position > const Duration(seconds: 2),
        reason: '初始文件未播放：${player.error}',
      );
      await player.pause();
      final pausedPosition = player.position;
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('player-quality-button')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await _captureSurface(surfaceKey, 'quality');
      await tester.tap(find.byKey(const ValueKey('player-choice-video-1')));
      await _pumpUntil(
        tester,
        () =>
            player.item.id == 'video-1' &&
            player.initialized &&
            !selection.switching,
        reason: '清晰度切换未完成：${player.error} / ${selection.error}',
      );
      await tester.pumpAndSettle();
      expect(player.playing, isFalse);
      expect(
        (player.position - pausedPosition).inMilliseconds.abs(),
        lessThan(1000),
      );
      expect(repository.savedProgress['video-0'], greaterThan(1000));
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
      expect(player.error, isNull);
      expect(tester.takeException(), isNull);
      debugPrint(
        'NATIVE_QUALITY_OK: ${player.item.id} position=${player.position} paused=${!player.playing}',
      );

      await tester.tap(find.byKey(const ValueKey('player-episodes-button')));
      await tester.pumpAndSettle();
      await _captureSurface(surfaceKey, 'episodes');
      await tester.tap(find.byKey(const ValueKey('player-choice-video-2')));
      await _pumpUntil(
        tester,
        () =>
            player.item.id == 'video-2' &&
            player.initialized &&
            player.position >= const Duration(seconds: 3),
        reason: '选集未从目标进度播放：${player.error} / ${selection.error}',
      );
      expect(player.playing, isTrue);
      expect(player.position, lessThan(const Duration(seconds: 8)));
      expect(player.error, isNull);
      expect(server.authFailures, 0);
      expect(server.rangeRequests, greaterThanOrEqualTo(3));
      expect(tester.takeException(), isNull);
      debugPrint(
        'NATIVE_EPISODE_OK: ${player.item.id} position=${player.position} ranges=${server.rangeRequests}',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      selection.dispose();
      interaction.dispose();
      await player.shutdown();
      await relay.close();
      await server.close();
      catalog.dispose();
      media.dispose();
    }
  });
}

/// 留存隔离窗口中的选择面板，截图不包含宿主桌面或其他应用。
Future<void> _captureSurface(GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      '${Directory.systemTemp.path}/luma_player_selection_smoke',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('SELECTION_SCREENSHOT: ${file.path}');
  } finally {
    image.dispose();
  }
}

/// 在真实宿主中等待解码器或弹层状态；超时报告失败阶段。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: reason);
  await tester.pump();
}

/// 三个内存文件分别表示第一集两个版本和第二集，记录每个文件独立的进度。
class _SelectionMediaRepository extends MockMediaRepository {
  _SelectionMediaRepository() {
    final fixtures = buildTvSmokeMediaItems();
    for (var index = 0; index < 3; index++) {
      final item = fixtures[index].copyWith(
        title: index == 2 ? '隔离剧集 第二集' : '隔离剧集 第一集',
        libraryKind: 'tv',
        catalogItemId: 'selection-series',
        resolution: index == 1 ? '1080p' : '720p',
        duration: const Duration(seconds: 30),
        progress: index == 2 ? 0.1 : 0,
        thumbnailUrl: '',
        cardThumbnailUrl: '',
      );
      items[item.id] = item;
    }
  }

  final Map<String, MediaItem> items = {};
  final Map<String, int> savedProgress = {};

  @override
  Future<MediaItem> loadDetail(String id) async => items[id]!;

  @override
  Future<MediaItem> updateProgress(String id, int positionMs) async {
    savedProgress[id] = positionMs;
    final updated = items[id]!.copyWith(progress: positionMs / 30000);
    items[id] = updated;
    return updated;
  }
}

/// 提供同集双版本的真实作品契约，不依赖测试设备上的现有库。
class _SelectionCatalogRepository implements CatalogRepository {
  _SelectionCatalogRepository(this.media);
  final _SelectionMediaRepository media;

  @override
  Future<CatalogItem> detail(String id) async => CatalogItem(
    id: id,
    sourceId: 'isolated',
    kind: CatalogKind.series,
    title: '隔离剧集',
    year: 2026,
    mediaCount: 3,
    episodeCount: 2,
    completedCount: 0,
    playableMediaId: 'video-0',
    thumbnailUrl: '',
    posterUrl: '',
    durationMs: 30000,
    resolution: '720p',
    progressMs: 0,
    completed: false,
    updatedAt: DateTime(2026, 10, 10),
    episodes: [
      for (final item in media.items.values)
        CatalogEpisode(
          id: 'episode-${item.id}',
          seasonNumber: 1,
          episodeNumber: item.id == 'video-2' ? 2 : 1,
          title: item.title,
          mediaId: item.id,
          durationMs: 30000,
          resolution: item.resolution,
          progressMs: (item.progress * 30000).round(),
          completed: false,
          thumbnailUrl: '',
        ),
    ],
  );

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async => [
    await detail('selection-series'),
  ];

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async => CatalogFavorite(favorite: favorite, revision: revision + 1);
}
