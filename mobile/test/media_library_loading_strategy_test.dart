// 媒体库加载策略测试覆盖图片瀑布流骨架和影视列表入场缓存门控。
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
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_collection_page.dart';
import 'package:luma/features/library/library_page.dart';
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
