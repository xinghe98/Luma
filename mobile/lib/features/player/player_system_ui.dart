import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PlayerSystemUiSession {
  Orientation? _entryOrientation;
  bool _portrait = false;
  bool _canLockOrientation = false;
  bool _entered = false;

  bool get portrait => _portrait;
  bool get canRotate => _canLockOrientation;

  Future<void> enter({
    required bool portraitVideo,
    required Orientation entryOrientation,
    required double shortestSide,
  }) async {
    if (_entered) return;
    _entered = true;
    _entryOrientation = entryOrientation;
    _portrait = portraitVideo;
    _canLockOrientation = shortestSide < 600;
    if (_canLockOrientation) await _applyOrientation();
    await _setImmersiveBestEffort();
  }

  Future<void> rotate() async {
    if (!_entered || !_canLockOrientation) return;
    _portrait = !_portrait;
    await _applyOrientation();
  }

  Future<void> _applyOrientation() => SystemChrome.setPreferredOrientations(
    _portrait
        ? const [DeviceOrientation.portraitUp]
        : const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
  );

  Future<void> _setImmersiveBestEffort() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } on PlatformException {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> exit() async {
    if (!_entered) return;
    _entered = false;
    if (_canLockOrientation) {
      final entry = _entryOrientation;
      await SystemChrome.setPreferredOrientations(
        entry == Orientation.landscape
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [DeviceOrientation.portraitUp],
      );
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_canLockOrientation) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
      await SystemChrome.setPreferredOrientations(const []);
    }
  }
}
