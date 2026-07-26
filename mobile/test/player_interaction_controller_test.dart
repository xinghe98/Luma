import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/player/player_device_controls.dart';
import 'package:luma/features/player/player_interaction_controller.dart';

void main() {
  Future<_Harness> createHarness() async {
    final media = MediaController(MockMediaRepository());
    await media.load();
    final item = media.items.firstWhere((item) => item.type == MediaType.video);
    final player = PlayerController(item: item, media: media);
    final devices = _FakeDeviceControls();
    final interaction = PlayerInteractionController(
      player: player,
      deviceControls: devices,
    );
    await interaction.initialize();
    return _Harness(media, player, interaction, devices);
  }

  test(
    'horizontal gesture previews a clamped seek and commits on release',
    () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);
      final origin = harness.player.position;

      harness.interaction.beginPan(
        const Offset(250, 250),
        const Size(500, 500),
      );
      harness.interaction.updatePan(const Offset(250, 0));

      expect(harness.interaction.mode, PlayerGestureMode.seek);
      expect(harness.player.scrubbing, isTrue);
      expect(harness.interaction.seekTarget, greaterThan(origin));
      expect(
        harness.interaction.seekTarget,
        lessThanOrEqualTo(harness.player.duration),
      );

      harness.interaction.endPan();
      expect(harness.player.scrubbing, isFalse);
      expect(harness.player.position, harness.interaction.seekTarget);
    },
  );

  test(
    'left and right vertical gestures control brightness and volume',
    () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      harness.interaction.beginPan(
        const Offset(100, 250),
        const Size(500, 500),
      );
      harness.interaction.updatePan(const Offset(0, -187.5));
      expect(harness.interaction.mode, PlayerGestureMode.brightness);
      expect(harness.interaction.brightness, 1);
      harness.interaction.endPan();
      await Future<void>.delayed(Duration.zero);
      expect(harness.devices.brightness, 1);

      harness.interaction.beginPan(
        const Offset(400, 250),
        const Size(500, 500),
      );
      harness.interaction.updatePan(const Offset(0, 187.5));
      expect(harness.interaction.mode, PlayerGestureMode.volume);
      expect(harness.interaction.volume, 0);
      harness.interaction.endPan();
      await Future<void>.delayed(Duration.zero);
      expect(harness.devices.volume, 0);
    },
  );

  test(
    'double taps use thirds and locked mode blocks playback gestures',
    () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);
      final origin = harness.player.position;

      harness.interaction.handleDoubleTap(290, 300);
      expect(harness.player.position, origin + const Duration(seconds: 10));
      expect(harness.interaction.hudKind, PlayerHudKind.forward);

      harness.player.setLocked(true);
      final lockedPosition = harness.player.position;
      harness.interaction.handleDoubleTap(10, 300);
      expect(harness.player.position, lockedPosition);
    },
  );

  test(
    'long press temporarily uses 2x speed and restores the prior speed',
    () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);
      harness.player.setSpeed(1.25);
      harness.player.togglePlay();

      harness.interaction.beginLongPress();
      expect(harness.player.speed, 2);
      expect(harness.interaction.hudKind, PlayerHudKind.speed);

      harness.interaction.endLongPress();
      expect(harness.player.speed, 1.25);
    },
  );

  test(
    'middle vertical drags are ignored to reduce accidental changes',
    () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      harness.interaction.beginPan(
        const Offset(250, 250),
        const Size(500, 500),
      );
      harness.interaction.updatePan(const Offset(0, 50));

      expect(harness.interaction.mode, PlayerGestureMode.ignored);
      expect(harness.devices.volume, 0.5);
      expect(harness.devices.brightness, 0.5);
    },
  );

  test(
    'unavailable device controls do not show vertical gesture HUDs',
    () async {
      final media = MediaController(MockMediaRepository());
      await media.load();
      final item = media.items.firstWhere(
        (item) => item.type == MediaType.video,
      );
      final player = PlayerController(item: item, media: media);
      final devices = _FakeDeviceControls()
        ..volumeAvailable = false
        ..brightnessAvailable = false;
      final interaction = PlayerInteractionController(
        player: player,
        deviceControls: devices,
      );
      await interaction.initialize();
      addTearDown(() {
        interaction.dispose();
        player.dispose();
        media.dispose();
      });

      interaction.beginPan(const Offset(100, 250), const Size(500, 500));
      interaction.updatePan(const Offset(0, -100));
      expect(interaction.mode, PlayerGestureMode.ignored);
      expect(interaction.hudKind, PlayerHudKind.hidden);

      interaction.endPan();
      interaction.beginPan(const Offset(400, 250), const Size(500, 500));
      interaction.updatePan(const Offset(0, -100));
      expect(interaction.mode, PlayerGestureMode.ignored);
      expect(interaction.hudKind, PlayerHudKind.hidden);
    },
  );
}

class _Harness {
  const _Harness(this.media, this.player, this.interaction, this.devices);

  final MediaController media;
  final PlayerController player;
  final PlayerInteractionController interaction;
  final _FakeDeviceControls devices;

  void dispose() {
    interaction.dispose();
    player.dispose();
    media.dispose();
  }
}

class _FakeDeviceControls implements PlayerDeviceControls {
  double volume = 0.5;
  double brightness = 0.5;
  bool volumeAvailable = true;
  bool brightnessAvailable = true;

  @override
  Future<PlayerDeviceState> readState() async => PlayerDeviceState(
    volume: volume,
    brightness: brightness,
    volumeAvailable: volumeAvailable,
    brightnessAvailable: brightnessAvailable,
  );

  @override
  Future<void> restoreBrightness() async {
    brightness = 0.5;
  }

  @override
  Future<bool> setBrightness(double value) async {
    brightness = value;
    return true;
  }

  @override
  Future<bool> setVolume(double value) async {
    volume = value;
    return true;
  }
}
