import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/details/details_controller.dart';
import 'package:luma/features/details/dialogs/image_preview_dialog.dart';
import 'package:luma/features/details/media_detail_page.dart';
import 'package:luma/features/details/widgets/detail_actions.dart';
import 'package:luma/features/details/widgets/media_metadata.dart';
import 'package:luma/shared/layout/surface_card.dart';
import 'package:luma/shared/media/authenticated_media_image.dart';
import 'package:luma/shared/media/media_artwork.dart';
import 'package:luma/shared/media/media_card.dart';

void main() {
  testWidgets('detail actions prioritize playback and keep favorite compact', (
    tester,
  ) async {
    final item = buildMediaFixtures().firstWhere(
      (item) => item.type == MediaType.video,
    );
    final media = MediaController(MockMediaRepository())..remember(item);
    final controller = DetailsController(mediaId: item.id, media: media);
    addTearDown(() {
      controller.dispose();
      media.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: DetailActions(controller: controller),
          ),
        ),
      ),
    );

    final play = tester.getRect(find.byType(FilledButton));
    final favorite = tester.getRect(
      find.byKey(const ValueKey('detail-favorite-action')),
    );
    expect(play.center.dy, favorite.center.dy);
    expect(play.right, lessThan(favorite.left));
    expect(favorite.width, LumaLayout.buttonHeight);
    expect(favorite.height, LumaLayout.buttonHeight);
  });

  testWidgets('video metadata cards are centered as a group', (tester) async {
    final item = buildMediaFixtures().firstWhere(
      (item) => item.type == MediaType.video,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 600, child: MediaMetadata(item: item)),
          ),
        ),
      ),
    );

    final cards = find.byType(SurfaceCard);
    expect(cards, findsNWidgets(4));
    final first = tester.getRect(cards.at(0));
    final last = tester.getRect(cards.at(3));
    final metadata = tester.getRect(find.byType(MediaMetadata));
    expect((first.left + last.right) / 2, closeTo(metadata.center.dx, 0.1));
  });

  testWidgets('video detail waits for the actual route transition', (
    tester,
  ) async {
    final repository = _CountingDetailRepository();
    final dependencies = AppDependencies(
      mediaRepository: repository,
      connectionService: MockConnectionService(),
    );
    addTearDown(dependencies.dispose);
    final item = buildMediaFixtures().firstWhere(
      (entry) => entry.type == MediaType.video,
    );

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  PageRouteBuilder<void>(
                    transitionDuration: const Duration(seconds: 1),
                    transitionsBuilder: (_, animation, _, child) =>
                        FadeTransition(opacity: animation, child: child),
                    pageBuilder: (_, _, _) => MediaDetailPage(
                      mediaId: item.id,
                      initialItem: item,
                      heroTag: 'detail-transition',
                    ),
                  ),
                ),
                child: const Text('打开媒体详情'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开媒体详情'));
    await tester.pump();
    expect(repository.detailCalls, 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(repository.detailCalls, 0);
    await tester.pumpAndSettle();
    expect(repository.detailCalls, 1);
  });

  testWidgets('image hero source and detail reuse the thumbnail cache key', (
    tester,
  ) async {
    final item = buildMediaFixtures()
        .firstWhere((entry) => entry.type == MediaType.image)
        .copyWith(thumbnailUrl: '/thumbnail');
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: MockConnectionService(),
    );
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: MediaCard(
                item: item,
                heroTag: 'recent-${item.id}',
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    final source = tester.widget<AuthenticatedMediaImage>(
      find.byType(AuthenticatedMediaImage),
    );
    expect(source.cacheWidth, MediaArtwork.heroThumbnailCacheWidth);
    expect(source.cacheHeight, isNull);

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: MediaDetailPage(
            mediaId: item.id,
            initialItem: item,
            heroTag: 'recent-${item.id}',
          ),
        ),
      ),
    );
    await tester.pump();
    final target = tester.widget<AuthenticatedMediaImage>(
      find.byType(AuthenticatedMediaImage),
    );
    expect(target.cacheWidth, MediaArtwork.heroThumbnailCacheWidth);
    expect(target.cacheHeight, isNull);
  });

  testWidgets('image preview uses the source Hero without a colored barrier', (
    tester,
  ) async {
    final item = buildMediaFixtures().firstWhere(
      (entry) => entry.type == MediaType.image,
    );
    const heroTag = 'image-preview-route';
    ImagePreviewAction? action;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Hero(
                tag: heroTag,
                child: Material(
                  child: InkWell(
                    onTap: () async {
                      action = await showImagePreviewDialog(
                        context,
                        item,
                        heroTag: heroTag,
                      );
                    },
                    child: const SizedBox(
                      width: 120,
                      height: 120,
                      child: Text('打开图片'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开图片'));
    await tester.pumpAndSettle();

    expect(find.byType(ImagePreviewDialog), findsOneWidget);
    final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
    expect(
      barriers.every(
        (barrier) => barrier.color == null || barrier.color!.a == 0,
      ),
      isTrue,
    );
    final route = ModalRoute.of(
      tester.element(find.byType(ImagePreviewDialog)),
    );
    expect(route, isA<PageRoute<void>>());
    expect(route?.opaque, isTrue);
    final previewHero = tester.widget<Hero>(
      find.descendant(
        of: find.byType(ImagePreviewDialog),
        matching: find.byType(Hero),
      ),
    );
    expect(previewHero.tag, heroTag);
    expect(previewHero.flightShuttleBuilder, isNotNull);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('详情'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(action, isNull);
    await tester.pumpAndSettle();
    expect(action, ImagePreviewAction.openDetails);
  });
}

class _CountingDetailRepository extends MockMediaRepository {
  var detailCalls = 0;

  @override
  Future<MediaItem> loadDetail(String id) {
    detailCalls++;
    return super.loadDetail(id);
  }
}
