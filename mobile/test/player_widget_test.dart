import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/player/player_device_controls.dart';
import 'package:luma/features/player/player_interaction_controller.dart';
import 'package:luma/features/player/widgets/player_controls.dart';
import 'package:luma/features/player/widgets/player_feedback_hud.dart';
import 'package:luma/features/player/widgets/player_gesture_layer.dart';

void main() {
  testWidgets('right-side double tap seeks and shows Chinese feedback', (
    tester,
  ) async {
    final harness = _WidgetHarness.create();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              PlayerGestureLayer(interaction: harness.interaction),
              PlayerFeedbackHud(interaction: harness.interaction),
            ],
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(PlayerGestureLayer));
    final point = Offset(rect.right - 80, rect.center.dy);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(point);
    await tester.pump();

    expect(find.text('快进 10 秒'), findsOneWidget);
    expect(harness.interaction.hudKind, PlayerHudKind.forward);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('locked controls expose a clear 48dp unlock action', (
    tester,
  ) async {
    final harness = _WidgetHarness.create();
    addTearDown(harness.dispose);
    harness.player.setLocked(true);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: harness.player,
            builder: (context, _) => PlayerControls(
              controller: harness.player,
              onBack: () {},
              onRotate: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('已锁定，点击解锁'), findsOneWidget);
    final buttonSize = tester.getSize(find.byType(FilledButton));
    expect(buttonSize.height, greaterThanOrEqualTo(48));

    await tester.tap(find.text('已锁定，点击解锁'));
    await tester.pump();
    expect(harness.player.locked, isFalse);
    expect(find.byTooltip('旋转屏幕'), findsOneWidget);
  });
}

class _WidgetHarness {
  const _WidgetHarness(this.media, this.player, this.interaction);

  final MediaController media;
  final PlayerController player;
  final PlayerInteractionController interaction;

  static _WidgetHarness create() {
    final media = MediaController(MockMediaRepository());
    final item = buildMediaFixtures().first;
    final player = PlayerController(item: item, media: media);
    final interaction = PlayerInteractionController(
      player: player,
      deviceControls: _NoopDeviceControls(),
    );
    return _WidgetHarness(media, player, interaction);
  }

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
