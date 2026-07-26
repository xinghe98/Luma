import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/player/player_device_controls.dart';
import 'package:luma/features/player/player_interaction_controller.dart';

void main() {
  Future<_Harness> createHarness(WidgetTester tester) async {
    final media = MediaController(MockMediaRepository());
    final loading = media.load();
    await tester.pump(const Duration(milliseconds: 650));
    await loading;
    final item = media.items.firstWhere((item) => item.type == MediaType.video);
    final player = PlayerController(item: item, media: media);
    final interaction = PlayerInteractionController(
      player: player,
      deviceControls: _NoopDeviceControls(),
    );
    return _Harness(media, player, interaction);
  }

  testWidgets('controls automatically hide after four seconds of inactivity', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    try {
      harness.player.start();
      expect(harness.player.controlsVisible, isTrue);

      await tester.pump(const Duration(seconds: 3, milliseconds: 999));
      expect(harness.player.controlsVisible, isTrue);

      await tester.pump(const Duration(milliseconds: 1));
      expect(harness.player.controlsVisible, isFalse);
    } finally {
      harness.dispose();
    }
  });

  testWidgets(
    'a tap on the video surface toggles controls and restarts hiding',
    (tester) async {
      final harness = await createHarness(tester);
      try {
        harness.interaction.handleTap();
        expect(harness.player.controlsVisible, isFalse);

        harness.interaction.handleTap();
        expect(harness.player.controlsVisible, isTrue);

        await tester.pump(const Duration(seconds: 4));
        expect(harness.player.controlsVisible, isFalse);
      } finally {
        harness.dispose();
      }
    },
  );
}

class _Harness {
  const _Harness(this.media, this.player, this.interaction);

  final MediaController media;
  final PlayerController player;
  final PlayerInteractionController interaction;

  void dispose() {
    interaction.dispose();
    player.dispose();
    media.dispose();
  }
}

class _NoopDeviceControls implements PlayerDeviceControls {
  @override
  Future<PlayerDeviceState> readState() async => const PlayerDeviceState(
    volume: 0.5,
    brightness: 0.5,
    volumeAvailable: true,
    brightnessAvailable: true,
  );

  @override
  Future<void> restoreBrightness() async {}

  @override
  Future<bool> setBrightness(double value) async => true;

  @override
  Future<bool> setVolume(double value) async => true;
}
