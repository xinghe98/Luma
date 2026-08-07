// 媒体库加载策略测试覆盖图片瀑布流骨架、影视列表入场缓存门控，
// 以及宽屏首屏内容不足时的自动追加分页。
// 测试使用 AppScope 与真实页面组件，并在每个尺寸用独立依赖隔离异步状态。
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_page.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/shared/media/media_card.dart';
import 'package:luma/shared/states/skeleton.dart';

/// 验证媒体库加载占位在手机、宽屏及明暗主题下保持正确结构。
void main() {
  final viewports = <({Size size, int columns})>[
    (size: const Size(390, 844), columns: 2),
    (size: const Size(1280, 800), columns: 5),
  ];

  for (final brightness in Brightness.values) {
    for (final viewport in viewports) {
      testWidgets(
        '图片库使用瀑布流骨架 ${brightness.name} ${viewport.size.width.toInt()}',
        (tester) async {
          tester.view.physicalSize = viewport.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final dependencies = AppDependencies(
            mediaRepository: MockMediaRepository(),
            catalogRepository: const EmptyCatalogRepository(),
            connectionService: MockConnectionService(),
          );
          addTearDown(dependencies.dispose);

          await tester.pumpWidget(
            AppScope(
              dependencies: dependencies,
              child: MaterialApp(
                theme: brightness == Brightness.light
                    ? LumaTheme.light()
                    : LumaTheme.dark(),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: viewport.size,
                    disableAnimations: true,
                  ),
                  child: LibraryPage(
                    type: MediaType.image,
                    pageSize: 18,
                    onOpenMedia: (_, {heroTag}) {},
                    onOpenSearch: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          expect(find.byType(PhotoMasonrySkeleton), findsOneWidget);
          expect(find.byType(MediaGridSkeleton), findsNothing);
          final grid = tester.widget<MasonryGridView>(
            find.descendant(
              of: find.byType(PhotoMasonrySkeleton),
              matching: find.byType(MasonryGridView),
            ),
          );
          final delegate =
              grid.gridDelegate
                  as SliverSimpleGridDelegateWithFixedCrossAxisCount;
          expect(delegate.crossAxisCount, viewport.columns);
          final boxes = find.descendant(
            of: find.byType(PhotoMasonrySkeleton),
            matching: find.byType(SkeletonBox),
          );
          expect(boxes, findsNWidgets(10));
          expect(
            tester.getSize(boxes.at(0)).height,
            isNot(tester.getSize(boxes.at(1)).height),
          );

          await tester.pump(const Duration(milliseconds: 100));
        },
      );
    }
  }

  for (final viewport in viewports) {
    testWidgets('影视完整列表入场后才恢复屏外缓存 ${viewport.size.width.toInt()}', (
      tester,
    ) async {
      tester.view.physicalSize = viewport.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dependencies = AppDependencies(
        mediaRepository: MockMediaRepository(),
        catalogRepository: const EmptyCatalogRepository(),
        connectionService: MockConnectionService(),
      );
      addTearDown(dependencies.dispose);

      await tester.pumpWidget(
        AppScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: LumaTheme.light(),
            home: Scaffold(
              body: CatalogCollectionBody(
                kind: CatalogKind.movie,
                initialItems: [_catalogItem()],
                onOpenCatalog: (_, {heroTag}) {},
              ),
            ),
          ),
        ),
      );

      final scroll = find.byKey(const PageStorageKey('catalog-scroll-movie'));
      expect(tester.widget<CustomScrollView>(scroll).cacheExtent, 0);

      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<CustomScrollView>(scroll).cacheExtent,
        LumaLayout.scrollCacheExtent,
      );
    });
  }

  testWidgets('宽屏首屏内容不足时自动追加下一页', (tester) async {
    // 模拟 Windows 最大化：首屏仅 6 条时高度填不满，必须不依赖滚动事件继续分页。
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _PagedPersonalVideoRepository(total: 30, pageSize: 6);
    final dependencies = AppDependencies(
      mediaRepository: repository,
      catalogRepository: const EmptyCatalogRepository(),
      connectionService: MockConnectionService(),
    );
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: LumaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1600, 1000),
              disableAnimations: true,
            ),
            child: LibraryPage(
              type: MediaType.video,
              fixedLibraryKind: 'personal',
              title: '个人视频',
              pageSize: 6,
              onOpenMedia: (_, {heroTag}) {},
              onOpenSearch: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(repository.searchCalls, greaterThanOrEqualTo(2));
    expect(find.byType(MediaCard), findsWidgets);
    expect(find.textContaining('个人视频 '), findsAtLeastNWidgets(12));
  });

  testWidgets('个人视频标题与电视剧分区保持一致的上间距', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      catalogRepository: _ShelfCatalogRepository(),
      connectionService: MockConnectionService(),
    );
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: LumaTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1280, 900),
              disableAnimations: true,
            ),
            child: CatalogPage(
              onOpenCatalog: (_, {heroTag}) {},
              onOpenPersonalMedia: (_, {heroTag}) {},
              onOpenSearch: () {},
              onOpenMovies: (_) {},
              onOpenSeries: (_) {},
              onOpenPersonalVideos: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(LumaMotion.navigation);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();

    final seriesTitle = find.text('电视剧');
    final personalTitle = find.text('个人视频');
    expect(seriesTitle, findsOneWidget);
    expect(personalTitle, findsOneWidget);

    // 电视剧标题相对其分区顶边为 0（外层 Padding.top 包住整块）；
    // 个人视频有内容时标题也应带上 LumaSpacing.lg，与其它分区一致。
    final seriesTop = tester.getTopLeft(seriesTitle).dy;
    final personalTop = tester.getTopLeft(personalTitle).dy;
    final seriesShelfBottom = tester.getBottomLeft(find.text('查看全部').at(1)).dy;
    // 个人视频标题应明显低于电视剧货架，且与货架底部至少隔开 lg 量级间距。
    expect(personalTop - seriesShelfBottom, greaterThanOrEqualTo(LumaSpacing.md));
    expect(personalTop, greaterThan(seriesTop));
  });
}

CatalogItem _catalogItem() => CatalogItem(
  id: 'loading-strategy-movie',
  sourceId: 'source-1',
  kind: CatalogKind.movie,
  title: '加载策略测试影片',
  year: 2026,
  mediaCount: 1,
  episodeCount: 0,
  completedCount: 0,
  playableMediaId: 'media-1',
  thumbnailUrl: '',
  posterUrl: '',
  durationMs: 90 * 60 * 1000,
  resolution: '1080p',
  progressMs: 0,
  completed: false,
  updatedAt: DateTime(2026, 7, 30),
);

/// 返回可多页个人视频，用于验证首屏填不满时的自动 loadMore。
class _PagedPersonalVideoRepository extends MockMediaRepository {
  _PagedPersonalVideoRepository({required this.total, required this.pageSize});

  final int total;
  final int pageSize;
  var searchCalls = 0;

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async {
    searchCalls++;
    final size = limit ?? pageSize;
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + size).clamp(0, total);
    final items = [
      for (var index = start; index < end; index++)
        MediaItem(
          id: 'personal-video-$index',
          title: '个人视频 $index',
          type: MediaType.video,
          libraryKind: 'personal',
          duration: Duration(minutes: 5 + index),
          resolution: '1080p',
          format: 'MP4',
          fileSize: '1.0 GB',
          directory: '/videos',
          tags: const ['测试'],
          addedAt: DateTime(2026, 7, 19).subtract(Duration(days: index)),
          artSeed: index,
        ),
    ];
    return MediaListPage(
      items: items,
      nextCursor: end < total ? '$end' : null,
    );
  }
}

/// 电影/电视剧各返回一条，便于测量分区标题间距。
class _ShelfCatalogRepository implements CatalogRepository {
  const _ShelfCatalogRepository();

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async {
    final item = CatalogItem(
      id: 'shelf-${kind?.name ?? 'all'}',
      sourceId: 'source-1',
      kind: kind ?? CatalogKind.movie,
      title: kind == CatalogKind.series ? '测试剧集' : '测试电影',
      year: 2026,
      mediaCount: 1,
      episodeCount: kind == CatalogKind.series ? 8 : 0,
      completedCount: 0,
      playableMediaId: 'media-${kind?.name ?? 'all'}',
      thumbnailUrl: '',
      posterUrl: '',
      durationMs: 90 * 60 * 1000,
      resolution: '1080p',
      progressMs: 0,
      completed: false,
      updatedAt: DateTime(2026, 7, 30),
    );
    return [item];
  }

  @override
  Future<CatalogItem> detail(String id) async =>
      (await list()).firstWhere((item) => item.id == id);

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async => CatalogFavorite(favorite: favorite, revision: revision + 1);
}
