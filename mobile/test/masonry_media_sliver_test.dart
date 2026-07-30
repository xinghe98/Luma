import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/shared/interaction/luma_focusable_surface.dart';
import 'package:luma/shared/media/authenticated_media_image.dart';
import 'package:luma/shared/media/masonry_media_sliver.dart';
import 'package:luma/shared/media/masonry_media_tile.dart';
import 'package:luma/shared/media/media_artwork.dart';
import 'package:luma/shared/media/media_card.dart';
import 'package:luma/shared/media/responsive_media_grid.dart';

void main() {
  MediaItem item(int index) => MediaItem(
    id: 'image-$index',
    title: '图片 $index',
    type: MediaType.image,
    duration: Duration.zero,
    resolution: '1200×1600',
    format: 'JPG',
    fileSize: '',
    directory: '',
    tags: const [],
    addedAt: DateTime.utc(2026),
    artSeed: index,
    aspectRatio: index.isEven ? 0.75 : 1.5,
    thumbnailUrl: '/api/v1/media/image-$index/thumbnail',
  );

  testWidgets('瀑布流只构建视口附近的图片节点', (tester) async {
    final items = List.generate(200, item);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              MasonryMediaSliver(items: items, onTap: (_, {heroTag}) {}),
            ],
          ),
        ),
      ),
    );

    final builtTiles = find.byType(MasonryMediaTile).evaluate().length;
    expect(builtTiles, greaterThan(0));
    expect(builtTiles, lessThan(items.length));
    expect(find.byType(SliverLayoutBuilder), findsNothing);
  });

  testWidgets('瓷砖按物理边界等比例解码且不创建第二套网络占位图', (tester) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: MasonryMediaTile(item: item(0), onTap: () {}),
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<AuthenticatedMediaImage>(
      find.byType(AuthenticatedMediaImage),
    );
    expect(image.cacheWidth, 600);
    expect(image.cacheHeight, 800);
    expect(image.resizePolicy, ResizeImagePolicy.fit);
    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.splashFactory, NoSplash.splashFactory);
    expect(ink.overlayColor?.resolve({}), Colors.transparent);
    expect(find.byType(MediaArtwork), findsNothing);
  });

  testWidgets('影音网格不在滚动期间通过 SliverLayoutBuilder 重建', (tester) async {
    final items = List.generate(200, item);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              ResponsiveMediaSliverGrid(items: items, onTap: (_, {heroTag}) {}),
            ],
          ),
        ),
      ),
    );

    final builtCards = find.byType(MediaCard).evaluate().length;
    expect(builtCards, greaterThan(0));
    expect(builtCards, lessThan(items.length));
    expect(find.byType(SliverLayoutBuilder), findsNothing);
  });

  testWidgets('宽屏媒体卡片的双行标题不会溢出', (tester) async {
    const gridWidth = 1213.0;
    final cardWidth =
        (gridWidth - LumaSpacing.md * (LumaLayout.gridColumns(gridWidth) - 1)) /
        LumaLayout.gridColumns(gridWidth);
    final cardHeight = cardWidth / LumaLayout.mediaCardAspectRatio(gridWidth);
    final media = item(0).copyWith(title: '这是一段会在桌面媒体卡片中稳定换成两行显示的较长标题');

    await tester.pumpWidget(
      MaterialApp(
        theme: LumaTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: MediaCard(item: media, onTap: () {}),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<LumaFocusableSurface>(
        find.byType(LumaFocusableSurface),
      ).contentPadding,
      EdgeInsets.zero,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (name, viewport, gridWidth, theme) in [
    ('手机浅色', const Size(390, 844), 350.0, LumaTheme.light()),
    ('Windows 宽屏深色', const Size(1280, 800), 1213.0, LumaTheme.dark()),
  ]) {
    testWidgets('$name视频卡片的 hover 边框与文字保持内距', (tester) async {
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final columnCount = LumaLayout.gridColumns(gridWidth);
      final cardWidth =
          (gridWidth - LumaSpacing.md * (columnCount - 1)) / columnCount;
      final cardHeight = cardWidth / LumaLayout.mediaCardAspectRatio(gridWidth);
      final media = MediaItem(
        id: 'video-hover',
        title: '视频卡片标题',
        type: MediaType.video,
        duration: const Duration(minutes: 8),
        resolution: '1920×1080',
        format: 'MP4',
        fileSize: '',
        directory: '',
        tags: const [],
        addedAt: DateTime.utc(2026),
        artSeed: 1,
        aspectRatio: 16 / 9,
        thumbnailUrl: '/api/v1/media/video-hover/thumbnail',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: MediaCard(item: media, onTap: () {}),
              ),
            ),
          ),
        ),
      );

      final surface = tester.widget<LumaFocusableSurface>(
        find.byType(LumaFocusableSurface),
      );
      expect(surface.contentPadding, const EdgeInsets.all(LumaSpacing.xs));

      final cardSize = tester.getSize(find.byType(MediaCard));
      final cardRect = tester.getRect(find.byType(MediaCard));
      final titleRect = tester.getRect(find.text('视频卡片标题'));
      expect(titleRect.left - cardRect.left, greaterThanOrEqualTo(8));

      final inkFinder = find.descendant(
        of: find.byType(LumaFocusableSurface),
        matching: find.byType(InkWell),
      );
      tester.widget<InkWell>(inkFinder).onHover!(true);
      await tester.pumpAndSettle();

      final animated = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(LumaFocusableSurface),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final decoration = animated.foregroundDecoration as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(tester.getSize(find.byType(MediaCard)), cardSize);
      expect(tester.takeException(), isNull);
    });
  }
}
