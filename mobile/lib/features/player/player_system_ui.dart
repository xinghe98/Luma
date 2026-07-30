// 播放器系统 UI 会话协调移动端沉浸/方向与 Windows 播放器原生全屏。
// 全局 generation 隔离相邻移动端页面；桌面全屏由 media_kit_video 原生宿主管理。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

class PlayerSystemUiSession {
  /// 创建播放器系统 UI 会话；测试可替换桌面判定与原生全屏回调。
  PlayerSystemUiSession({
    bool? desktop,
    Future<void> Function()? enterDesktopFullScreen,
    Future<void> Function()? exitDesktopFullScreen,
  }) : _desktop = desktop,
       _enterDesktopFullScreen =
           enterDesktopFullScreen ?? defaultEnterNativeFullscreen,
       _exitDesktopFullScreen =
           exitDesktopFullScreen ?? defaultExitNativeFullscreen;

  static int _globalGeneration = 0;

  final bool? _desktop;
  final Future<void> Function() _enterDesktopFullScreen;
  final Future<void> Function() _exitDesktopFullScreen;
  Orientation? _entryOrientation;
  bool _portrait = false;
  bool _canLockOrientation = false;
  bool _entered = false;
  bool _fullScreen = false;

  bool get portrait => _portrait;
  bool get canRotate => _canLockOrientation;

  /// 当前会话是否运行在真实 Windows 桌面宿主；Flutter 测试保持移动端路径。
  bool get isDesktop =>
      _desktop ??
      (Platform.isWindows && Platform.environment['FLUTTER_TEST'] != 'true');

  /// 当前记录的 Windows 全屏状态；移动端始终为 false。
  bool get fullScreen => _fullScreen;

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
    _canLockOrientation = !isDesktop && shortestSide < 600;
    final generation = ++_globalGeneration;
    if (isDesktop) {
      _fullScreen = false;
      return;
    }
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

  /// 通过 media_kit_video 切换 Windows 播放器原生全屏。
  Future<bool> toggleFullScreen() async {
    if (!_entered || !isDesktop) return _fullScreen;
    final next = !_fullScreen;
    if (next) {
      await _enterDesktopFullScreen();
    } else {
      await _exitDesktopFullScreen();
    }
    _fullScreen = next;
    return next;
  }

  /// 优先退出 Windows 全屏；已是窗口模式时返回 false。
  Future<bool> exitFullScreen() async {
    if (!_entered || !isDesktop || !_fullScreen) return false;
    await _exitDesktopFullScreen();
    _fullScreen = false;
    return true;
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
    if (isDesktop) {
      if (_fullScreen) {
        await _exitDesktopFullScreen();
      }
      _fullScreen = false;
      return;
    }
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
