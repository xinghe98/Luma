import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'player_controller.dart';
import 'player_device_controls.dart';

enum PlayerGestureMode { idle, pending, seek, brightness, volume, ignored }

enum PlayerHudKind {
  hidden,
  seek,
  brightness,
  volume,
  backward,
  forward,
  play,
  pause,
  speed,
}

class PlayerInteractionController extends ChangeNotifier {
  PlayerInteractionController({
    required this.player,
    required PlayerDeviceControls deviceControls,
  }) : _deviceControls = deviceControls;

  static const gestureThreshold = 12.0;
  static const protectedEdge = 24.0;

  final PlayerController player;
  final PlayerDeviceControls _deviceControls;
  PlayerGestureMode _mode = PlayerGestureMode.idle;
  PlayerHudKind _hudKind = PlayerHudKind.hidden;
  Offset _totalDelta = Offset.zero;
  Size _surfaceSize = Size.zero;
  double _startX = 0;
  double _volume = 1;
  double _brightness = 0.5;
  double _startVolume = 1;
  double _startBrightness = 0.5;
  Duration _seekOrigin = Duration.zero;
  Duration _seekTarget = Duration.zero;
  double? _speedBeforeHold;
  Timer? _hudTimer;
  Timer? _deviceTimer;
  double? _pendingDeviceValue;
  bool _disposed = false;

  PlayerGestureMode get mode => _mode;
  PlayerHudKind get hudKind => _hudKind;
  bool get hudVisible => _hudKind != PlayerHudKind.hidden;
  double get volume => _volume;
  double get brightness => _brightness;
  Duration get seekTarget => _seekTarget;
  Duration get seekDelta => _seekTarget - _seekOrigin;
  double get seekProgress {
    final total = player.duration.inMilliseconds;
    return total <= 0 ? 0 : _seekTarget.inMilliseconds / total;
  }

  Future<void> initialize() async {
    final state = await _deviceControls.readState();
    if (_disposed) return;
    _volume = state.volume;
    _brightness = state.brightness;
  }

  void handleTap() {
    if (player.locked) {
      player.showLockHint();
      return;
    }
    player.toggleControls();
  }

  void handleDoubleTap(double localX, double width) {
    if (player.locked || width <= 0) {
      if (player.locked) player.showLockHint();
      return;
    }
    final third = width / 3;
    if (localX < third) {
      player.seekBy(-10, revealControls: false);
      _showHud(PlayerHudKind.backward);
    } else if (localX > third * 2) {
      player.seekBy(10, revealControls: false);
      _showHud(PlayerHudKind.forward);
    } else {
      final wasPlaying = player.playing;
      player.togglePlay(revealControls: false);
      _showHud(wasPlaying ? PlayerHudKind.pause : PlayerHudKind.play);
    }
  }

  void beginPan(Offset localPosition, Size size) {
    if (player.locked ||
        size.isEmpty ||
        localPosition.dx < protectedEdge ||
        localPosition.dx > size.width - protectedEdge) {
      _mode = PlayerGestureMode.ignored;
      if (player.locked) player.showLockHint();
      return;
    }
    _mode = PlayerGestureMode.pending;
    _totalDelta = Offset.zero;
    _surfaceSize = size;
    _startX = localPosition.dx;
    _startVolume = _volume;
    _startBrightness = _brightness;
    player.pauseAutoHide();
  }

  void updatePan(Offset delta) {
    if (_mode == PlayerGestureMode.idle || _mode == PlayerGestureMode.ignored) {
      return;
    }
    _totalDelta += delta;
    if (_mode == PlayerGestureMode.pending) _resolveGestureMode();
    switch (_mode) {
      case PlayerGestureMode.seek:
        _updateSeek();
        break;
      case PlayerGestureMode.brightness:
        _updateDeviceValue(isVolume: false);
        break;
      case PlayerGestureMode.volume:
        _updateDeviceValue(isVolume: true);
        break;
      case PlayerGestureMode.idle:
      case PlayerGestureMode.pending:
      case PlayerGestureMode.ignored:
        break;
    }
  }

  void _resolveGestureMode() {
    final dx = _totalDelta.dx.abs();
    final dy = _totalDelta.dy.abs();
    if (math.max(dx, dy) < gestureThreshold) return;
    if (dx >= dy) {
      _mode = PlayerGestureMode.seek;
      _seekOrigin = player.position;
      _seekTarget = _seekOrigin;
      player.beginScrub();
      _showHud(PlayerHudKind.seek, persistent: true);
      return;
    }
    if (_startX <= _surfaceSize.width * 0.4) {
      _mode = PlayerGestureMode.brightness;
      _showHud(PlayerHudKind.brightness, persistent: true);
    } else if (_startX >= _surfaceSize.width * 0.6) {
      _mode = PlayerGestureMode.volume;
      _showHud(PlayerHudKind.volume, persistent: true);
    } else {
      _mode = PlayerGestureMode.ignored;
    }
  }

  void _updateSeek() {
    final totalMs = player.duration.inMilliseconds;
    if (totalMs <= 0 || _surfaceSize.width <= 0) return;
    final adaptiveSpan = (totalMs * 0.1).clamp(30000, 120000);
    final spanMs = math.min(totalMs, adaptiveSpan).round();
    final deltaMs = (_totalDelta.dx / _surfaceSize.width * spanMs).round();
    final targetMs = (_seekOrigin.inMilliseconds + deltaMs).clamp(0, totalMs);
    _seekTarget = Duration(milliseconds: targetMs);
    player.updateScrub(_seekTarget);
    notifyListeners();
  }

  void _updateDeviceValue({required bool isVolume}) {
    if (_surfaceSize.height <= 0) return;
    final start = isVolume ? _startVolume : _startBrightness;
    final minimum = isVolume ? 0.0 : 0.05;
    final value = (start - _totalDelta.dy / (_surfaceSize.height * 0.75))
        .clamp(minimum, 1.0)
        .toDouble();
    if (isVolume) {
      _volume = value;
      _hudKind = PlayerHudKind.volume;
    } else {
      _brightness = value;
      _hudKind = PlayerHudKind.brightness;
    }
    _pendingDeviceValue = value;
    _deviceTimer ??= Timer(const Duration(milliseconds: 32), () {
      _deviceTimer = null;
      _flushDeviceValue();
    });
    notifyListeners();
  }

  void endPan({bool cancelled = false}) {
    final finishedMode = _mode;
    _mode = PlayerGestureMode.idle;
    _deviceTimer?.cancel();
    _deviceTimer = null;
    _flushDeviceValue();
    if (finishedMode == PlayerGestureMode.seek) {
      if (cancelled) {
        player.cancelScrub();
      } else {
        player.commitScrub();
      }
    }
    if (finishedMode != PlayerGestureMode.pending &&
        finishedMode != PlayerGestureMode.ignored) {
      _scheduleHudHide();
    }
    player.scheduleHide();
  }

  void _flushDeviceValue() {
    final value = _pendingDeviceValue;
    _pendingDeviceValue = null;
    if (value == null) return;
    if (_hudKind == PlayerHudKind.volume) {
      unawaited(_setVolume(value));
    } else if (_hudKind == PlayerHudKind.brightness) {
      unawaited(_deviceControls.setBrightness(value));
    }
  }

  Future<void> _setVolume(double value) async {
    final applied = await _deviceControls.setVolume(value);
    if (!applied && !_disposed) player.setLocalVolume(value);
  }

  void beginLongPress() {
    if (player.locked || !player.playing || _speedBeforeHold != null) return;
    _speedBeforeHold = player.speed;
    player.setPlaybackSpeed(2, revealControls: false);
    _showHud(PlayerHudKind.speed, persistent: true);
  }

  void endLongPress() {
    final previous = _speedBeforeHold;
    if (previous == null) return;
    _speedBeforeHold = null;
    player.setPlaybackSpeed(previous, revealControls: false);
    _scheduleHudHide();
  }

  void _showHud(PlayerHudKind kind, {bool persistent = false}) {
    _hudTimer?.cancel();
    _hudKind = kind;
    notifyListeners();
    if (!persistent) _scheduleHudHide();
  }

  void _scheduleHudHide() {
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 700), () {
      _hudKind = PlayerHudKind.hidden;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> restoreDeviceState() => _deviceControls.restoreBrightness();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hudTimer?.cancel();
    _deviceTimer?.cancel();
    super.dispose();
  }
}
