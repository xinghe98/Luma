import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
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
}
