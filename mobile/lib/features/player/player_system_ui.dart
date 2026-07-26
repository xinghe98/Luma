// 播放器系统 UI 会话协调沉浸模式与手机方向锁定。
// 全局 generation 保证相邻播放器页面的异步 enter/exit 不会互相覆盖。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PlayerSystemUiSession {
  static int _globalGeneration = 0;

  Orientation? _entryOrientation;
  bool _portrait = false;
  bool _canLockOrientation = false;
  bool _entered = false;

  bool get portrait => _portrait;
  bool get canRotate => _canLockOrientation;

  /// 进入沉浸模式并按视频方向锁定手机；平板保持系统当前方向。
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
    final generation = ++_globalGeneration;
    if (_canLockOrientation) {
      await _applyOrientationBestEffort();
      if (generation != _globalGeneration || !_entered) return;
    }
    await _setImmersiveBestEffort(generation);
  }

  /// 在横竖屏之间切换；会话已退出或设备不允许锁定时不执行操作。
  Future<void> rotate() async {
    if (!_entered || !_canLockOrientation) return;
    _portrait = !_portrait;
    final generation = ++_globalGeneration;
    await _applyOrientationBestEffort();
    if (generation != _globalGeneration || !_entered) return;
    await _setImmersiveBestEffort(generation);
  }

  Future<void> _applyOrientationBestEffort() => _setOrientationsBestEffort(
    _portrait
        ? const [DeviceOrientation.portraitUp]
        : const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
  );

  Future<void> _setImmersiveBestEffort(int generation) async {
    if (generation != _globalGeneration || !_entered) return;
    final immersiveApplied = await _setModeBestEffort(
      SystemUiMode.immersiveSticky,
    );
    if (immersiveApplied || generation != _globalGeneration || !_entered) {
      return;
    }
    await _setModeBestEffort(SystemUiMode.edgeToEdge);
  }

  /// 恢复进入播放器前的方向和系统栏，并丢弃被新会话取代的异步步骤。
  Future<void> exit() async {
    if (!_entered) return;
    _entered = false;
    final generation = ++_globalGeneration;
    try {
      if (_canLockOrientation) {
        final entry = _entryOrientation;
        await _setOrientationsBestEffort(
          entry == Orientation.landscape
              ? const [
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]
              : const [DeviceOrientation.portraitUp],
        );
        if (generation != _globalGeneration) return;
      }
      await _setModeBestEffort(SystemUiMode.edgeToEdge);
      if (generation != _globalGeneration) return;
    } finally {
      if (_canLockOrientation && generation == _globalGeneration) {
        await Future<void>.delayed(const Duration(milliseconds: 320));
        if (generation == _globalGeneration) {
          await _setOrientationsBestEffort(const []);
        }
      }
    }
  }

  Future<bool> _setModeBestEffort(SystemUiMode mode) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(mode);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _setOrientationsBestEffort(
    List<DeviceOrientation> orientations,
  ) async {
    try {
      await SystemChrome.setPreferredOrientations(orientations);
    } on Object {
      // 系统或宿主拒绝方向请求时，播放器仍按当前方向继续工作。
    }
  }
}
