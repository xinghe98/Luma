import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/player/player_controller.dart';

void main() {
  test('starting from the beginning ignores saved progress', () {
    final repository = MockMediaRepository();
    final media = MediaController(repository);
    final item = buildMediaFixtures().firstWhere(
      (item) => item.type == MediaType.video && item.progress > 0,
    );
    final player = PlayerController(
      item: item,
      media: media,
      startFromBeginning: true,
    );
    addTearDown(() {
      player.dispose();
      media.dispose();
    });

    expect(player.position, Duration.zero);
  });

  testWidgets('periodic progress saves only while playback is active', (
    tester,
  ) async {
    final harness = _PlayerHarness.create();
    harness.player.start();

    await tester.pump(const Duration(seconds: 30));
    expect(harness.repository.progressUpdates, 0);

    harness.player.togglePlay();
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(harness.repository.progressUpdates, 1);

    harness.player.togglePlay();
    await tester.pump();
    final updatesAfterPause = harness.repository.progressUpdates;
    await tester.pump(const Duration(seconds: 30));
    expect(harness.repository.progressUpdates, updatesAfterPause);
    harness.dispose();
  });

  testWidgets(
    'paused scrubbing, lifecycle persistence, and shutdown save progress',
    (tester) async {
      final harness = _PlayerHarness.create();
      addTearDown(harness.dispose);

      harness.player
        ..beginScrub()
        ..updateScrub(const Duration(seconds: 30))
        ..commitScrub();
      await tester.pump();
      expect(harness.repository.progressUpdates, 1);

      await harness.player.persistProgress();
      expect(harness.repository.progressUpdates, 2);

      await harness.player.shutdown();
      expect(harness.repository.progressUpdates, 3);
    },
  );
}

class _PlayerHarness {
  const _PlayerHarness(this.repository, this.media, this.player);

  final _CountingMediaRepository repository;
  final MediaController media;
  final PlayerController player;

  static _PlayerHarness create() {
    final repository = _CountingMediaRepository();
    final media = MediaController(repository);
    final item = buildMediaFixtures().firstWhere(
      (item) => item.type == MediaType.video,
    );
    media.remember(item, notify: false);
    return _PlayerHarness(
      repository,
      media,
      PlayerController(item: item, media: media),
    );
  }

  void dispose() {
    player.dispose();
    media.dispose();
  }
}

class _CountingMediaRepository extends MockMediaRepository {
  var progressUpdates = 0;

  @override
  Future<MediaItem> updateProgress(String id, int positionMs) async {
    progressUpdates++;
    return super.updateProgress(id, positionMs);
  }
}
