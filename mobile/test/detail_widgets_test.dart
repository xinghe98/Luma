import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/details/details_controller.dart';
import 'package:luma/features/details/widgets/detail_actions.dart';
import 'package:luma/features/details/widgets/media_metadata.dart';
import 'package:luma/shared/layout/surface_card.dart';

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
        home: Scaffold(body: Padding(
          padding: const EdgeInsets.all(16),
          child: DetailActions(controller: controller),
        )),
      ),
    );

    final play = tester.getRect(find.byType(FilledButton));
    final favorite = tester.getRect(
      find.byKey(const ValueKey('detail-favorite-action')),
    );
    expect(play.center.dy, favorite.center.dy);
    expect(play.right, lessThan(favorite.left));
    expect(favorite.width, 52);
    expect(favorite.height, 52);
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
}
