import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:luma/features/player/widgets/player_scene.dart';

void main() {
  testWidgets('right-side double tap seeks and shows Chinese feedback', (
    tester,
  ) async {
    final harness = _WidgetHarness.create();
    try {
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
    } finally {
      harness.dispose();
    }
  });

  testWidgets('locked controls expose a clear 48dp unlock action', (
    tester,
  ) async {
    final harness = _WidgetHarness.create();
    try {
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
    } finally {
      harness.dispose();
    }
  });

  testWidgets('playback errors are announced and can retry in place', (
    tester,
  ) async {
    final harness = _WidgetHarness.create(status: 'processing');
    try {
      harness.player.start();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: PlayerScene(
              controller: harness.player,
              interaction: harness.interaction,
              onBack: () {},
              onMinimize: () {},
              onRotate: null,
            ),
          ),
        ),
      );

      expect(find.text('重试播放'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('媒体尚未就绪')), findsOneWidget);
      await tester.tap(find.text('重试播放'));
      await tester.pump();
      expect(find.text('重试播放'), findsOneWidget);
    } finally {
      harness.dispose();
    }
  });

  testWidgets('desktop player exposes volume and keyboard controls', (
    tester,
  ) async {
    final harness = _WidgetHarness.create();
    var fullscreenToggles = 0;
    var escapeCalls = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: PlayerScene(
              controller: harness.player,
              interaction: harness.interaction,
              onBack: () {},
              onMinimize: () {},
              onRotate: null,
              isDesktop: true,
              onToggleFullScreen: () => fullscreenToggles++,
              onEscape: () => escapeCalls++,
            ),
          ),
        ),
      );

      expect(find.byTooltip('静音'), findsOneWidget);
      expect(find.byTooltip('进入全屏'), findsOneWidget);
      expect(find.byTooltip('锁定控制'), findsNothing);
      expect(find.byTooltip('旋转屏幕'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(harness.player.muted, isTrue);
      expect(harness.player.volume, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(fullscreenToggles, 1);
      expect(escapeCalls, 1);
    } finally {
      harness.dispose();
    }
  });
}

class _WidgetHarness {
  const _WidgetHarness(this.media, this.player, this.interaction);

  final MediaController media;
  final PlayerController player;
  final PlayerInteractionController interaction;

  static _WidgetHarness create({String? status}) {
    final media = MediaController(MockMediaRepository());
    final baseItem = buildMediaFixtures().first;
    final item = status == null ? baseItem : baseItem.copyWith(status: status);
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
