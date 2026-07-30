// 作品详情页测试覆盖刮削资料的渐进展示，确保刷新时保留已有内容。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_detail_page.dart';
import 'package:luma/features/catalog/widgets/catalog_detail_hero.dart';
import 'package:luma/features/catalog/widgets/catalog_detail_sections.dart';
import 'package:luma/shared/media/authenticated_media_image.dart';

void main() {
  testWidgets('catalog hero keeps poster and metadata side by side on phones', (
    tester,
  ) async {
    final item = CatalogItem(
      id: 'catalog-compact-hero',
      sourceId: 'source-1',
      kind: CatalogKind.movie,
      title: '手机横排详情',
      year: 2026,
      mediaCount: 1,
      episodeCount: 0,
      completedCount: 0,
      playableMediaId: 'media-1',
      thumbnailUrl: '/thumbnail',
      posterUrl: '/poster',
      durationMs: 5400000,
      resolution: '1080p',
      progressMs: 0,
      completed: false,
      updatedAt: DateTime(2026, 7, 26),
      communityRating: 8.4,
      genres: const [CatalogNamedValue(id: 'drama', name: '剧情')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 375,
              child: CatalogDetailHero(
                item: item,
                loadBackdrop: false,
                favorite: false,
                savingFavorite: false,
                onPlay: (_) {},
                onPlayFromStart: (_) {},
                onToggleFavorite: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final poster = find.byWidgetPredicate(
      (widget) => widget is AuthenticatedMediaImage && widget.path == '/poster',
    );
    final rating = find.text('★ 8.4');
    final posterRect = tester.getRect(poster);
    final ratingRect = tester.getRect(rating);
    expect(ratingRect.left, greaterThan(posterRect.right));
    expect(
      ratingRect.center.dy,
      inInclusiveRange(posterRect.top, posterRect.bottom),
    );
  });

  testWidgets('catalog detail keeps scraped content visible while refreshing', (
    tester,
  ) async {
    final item = CatalogItem(
      id: 'catalog-1',
      sourceId: 'source-1',
      kind: CatalogKind.movie,
      title: '三体',
      year: 2023,
      mediaCount: 1,
      episodeCount: 0,
      completedCount: 0,
      playableMediaId: 'media-1',
      thumbnailUrl: '',
      posterUrl: '',
      durationMs: 3600000,
      resolution: '1920×1080',
      progressMs: 0,
      completed: false,
      updatedAt: DateTime(2026, 7, 25),
      overview: '一段跨越时空的故事。',
      certification: 'PG-13',
      communityRating: 8.4,
      genres: [CatalogNamedValue(id: '18', name: '剧情')],
      credits: [
        CatalogCredit(
          personId: 'person-1',
          name: '演员',
          role: 'actor',
          character: '角色',
          order: 0,
        ),
      ],
      metadataStatus: 'refreshing',
      versions: const [
        CatalogVersion(
          mediaId: 'movie-4k',
          label: '4K HEVC',
          fileSize: 2147483648,
          durationMs: 3600000,
          resolution: '3840×2160',
          videoCodec: 'hevc',
          audioCodec: 'aac',
          audioTrackCount: 2,
          progressMs: 0,
          completed: false,
          selected: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CatalogDetailPage(
          catalogId: item.id,
          initialItem: item,
          repository: _CatalogDetailRepository(item),
          onOpenMedia: (_) {},
          onOpenMediaFromStart: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('剧情'), findsOneWidget);
    expect(find.text('★ 8.4'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('继续观看'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(OutlinedButton),
        matching: find.text('从头播放'),
      ),
      findsOneWidget,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -560));
    await tester.pump();
    expect(find.text('一段跨越时空的故事。'), findsOneWidget);
    expect(find.text('PG-13'), findsOneWidget);
    expect(find.text('演员'), findsOneWidget);
    expect(find.text('角色'), findsOneWidget);
    final avatarSize = tester.getSize(find.byType(ClipOval));
    expect(avatarSize.width, avatarSize.height);
    expect(avatarSize.width, 56);
    expect(find.text('本库其他版本'), findsOneWidget);
    expect(find.text('4K HEVC'), findsOneWidget);
    expect(find.text('资料正在更新'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('catalog detail saves a work favorite optimistically', (
    tester,
  ) async {
    final item = CatalogItem(
      id: 'catalog-favorite',
      sourceId: 'source-1',
      kind: CatalogKind.movie,
      title: '电影',
      year: null,
      mediaCount: 1,
      episodeCount: 0,
      completedCount: 0,
      playableMediaId: 'media-1',
      thumbnailUrl: '',
      posterUrl: '',
      durationMs: null,
      resolution: '',
      progressMs: 0,
      completed: false,
      updatedAt: DateTime(2026, 7, 25),
    );
    final repository = _CatalogDetailRepository(item);

    await tester.pumpWidget(
      MaterialApp(
        home: CatalogDetailPage(
          catalogId: item.id,
          initialItem: item,
          repository: repository,
          onOpenMedia: (_) {},
          onOpenMediaFromStart: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('收藏'));
    await tester.pump();

    expect(repository.favoriteCalls, 1);
    expect(find.text('已收藏'), findsOneWidget);
  });

  testWidgets('catalog detail waits for the route transition before refresh', (
    tester,
  ) async {
    final item = CatalogItem(
      id: 'catalog-delayed-refresh',
      sourceId: 'source-1',
      kind: CatalogKind.series,
      title: '延迟刷新剧集',
      year: 2026,
      mediaCount: 1,
      episodeCount: 1,
      completedCount: 0,
      playableMediaId: 'episode-1',
      thumbnailUrl: '/thumbnail',
      posterUrl: '/poster',
      durationMs: null,
      resolution: '1080p',
      progressMs: 0,
      completed: false,
      updatedAt: DateTime(2026, 7, 26),
      backdropUrl: '/backdrop',
    );
    final repository = _CatalogDetailRepository(item);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  PageRouteBuilder<void>(
                    transitionDuration: const Duration(seconds: 1),
                    transitionsBuilder: (_, animation, _, child) =>
                        FadeTransition(opacity: animation, child: child),
                    pageBuilder: (_, _, _) => CatalogDetailPage(
                      catalogId: item.id,
                      initialItem: item,
                      repository: repository,
                      onOpenMedia: (_) {},
                      onOpenMediaFromStart: (_) {},
                    ),
                  ),
                ),
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pump();
    await tester.pump();

    expect(find.text('延迟刷新剧集'), findsOneWidget);
    expect(repository.detailCalls, 0);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AuthenticatedMediaImage && widget.path == '/backdrop',
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AuthenticatedMediaImage && widget.path == '/poster',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.detailCalls, 0);
    await tester.pumpAndSettle();
    expect(repository.detailCalls, 1);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AuthenticatedMediaImage && widget.path == '/backdrop',
      ),
      findsOneWidget,
    );
  });

  testWidgets('series detail lazily builds episodes near the viewport', (
    tester,
  ) async {
    final episodes = List.generate(
      60,
      (index) => CatalogEpisode(
        id: 'episode-$index',
        seasonNumber: 1,
        episodeNumber: index + 1,
        title: '第 ${index + 1} 集',
        mediaId: 'media-$index',
        durationMs: 2700000,
        resolution: '1080p',
        progressMs: 0,
        completed: false,
        thumbnailUrl: '',
      ),
    );
    final item = CatalogItem(
      id: 'catalog-lazy-series',
      sourceId: 'source-1',
      kind: CatalogKind.series,
      title: '长剧集',
      year: 2026,
      mediaCount: episodes.length,
      episodeCount: episodes.length,
      completedCount: 0,
      playableMediaId: episodes.first.mediaId,
      thumbnailUrl: '',
      posterUrl: '',
      durationMs: null,
      resolution: '1080p',
      progressMs: 0,
      completed: false,
      updatedAt: DateTime(2026, 7, 26),
      episodes: episodes,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CatalogDetailPage(
          catalogId: item.id,
          initialItem: item,
          repository: _CatalogDetailRepository(item),
          onOpenMedia: (_) {},
          onOpenMediaFromStart: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
    await tester.pump();

    final builtEpisodes = find.byType(CatalogEpisodeTile).evaluate().length;
    expect(builtEpisodes, greaterThan(0));
    expect(builtEpisodes, lessThan(episodes.length));
  });

  testWidgets(
    'catalog detail keeps stale content on refresh errors and retries',
    (tester) async {
      final item = _compactCatalogItem('保留的作品');
      final repository = _CatalogDetailRepository(item)..failDetail = true;

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogDetailPage(
            catalogId: item.id,
            initialItem: item,
            repository: repository,
            onOpenMedia: (_) {},
            onOpenMediaFromStart: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('保留的作品'), findsOneWidget);
      expect(find.text('作品资料刷新失败，当前仍显示上次内容。'), findsOneWidget);
      repository.failDetail = false;
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(repository.detailCalls, 2);
    },
  );

  testWidgets(
    'stale refresh does not overwrite an in-flight favorite revision',
    (tester) async {
      final item = _compactCatalogItem('收藏竞态');
      final repository = _CatalogDetailRepository(item)
        ..detailCompleter = Completer<CatalogItem>()
        ..favoriteCompleter = Completer<CatalogFavorite>();

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogDetailPage(
            catalogId: item.id,
            initialItem: item,
            repository: repository,
            onOpenMedia: (_) {},
            onOpenMediaFromStart: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('收藏'));
      await tester.pump();
      repository.detailCompleter!.complete(item);
      await tester.pump();

      expect(find.text('已收藏'), findsOneWidget);
      repository.favoriteCompleter!.complete(
        const CatalogFavorite(favorite: true, revision: 1),
      );
      await tester.pump();
      expect(find.byTooltip('取消收藏'), findsOneWidget);
    },
  );

  testWidgets(
    'catalog hero has natural height on narrow screens and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final item = _compactCatalogItem('很长的作品标题也必须完整适配窄屏');

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(2),
            ),
            child: CatalogDetailPage(
              catalogId: item.id,
              initialItem: item,
              repository: _CatalogDetailRepository(item),
              onOpenMedia: (_) {},
              onOpenMediaFromStart: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('很长的作品标题也必须完整适配窄屏'), findsOneWidget);
    },
  );
}

CatalogItem _compactCatalogItem(String title) => CatalogItem(
  id: 'catalog-compact',
  sourceId: 'source-1',
  kind: CatalogKind.movie,
  title: title,
  year: 2026,
  mediaCount: 1,
  episodeCount: 0,
  completedCount: 0,
  playableMediaId: 'media-1',
  thumbnailUrl: '',
  posterUrl: '',
  durationMs: 3600000,
  resolution: '1080p',
  progressMs: 0,
  completed: false,
  updatedAt: DateTime(2026, 7, 26),
);

class _CatalogDetailRepository implements CatalogRepository {
  _CatalogDetailRepository(this.item);

  final CatalogItem item;
  var favoriteCalls = 0;
  var detailCalls = 0;
  var failDetail = false;
  Completer<CatalogItem>? detailCompleter;
  Completer<CatalogFavorite>? favoriteCompleter;

  @override
  Future<CatalogItem> detail(String id) async {
    detailCalls++;
    if (failDetail) throw StateError('刷新失败');
    final completer = detailCompleter;
    if (completer != null) return completer.future;
    return item;
  }

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async {
    favoriteCalls++;
    final completer = favoriteCompleter;
    if (completer != null) return completer.future;
    return CatalogFavorite(favorite: favorite, revision: revision + 1);
  }

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async =>
      [];
}
