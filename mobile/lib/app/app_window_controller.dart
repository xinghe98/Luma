// Windows 窗口控制器负责应用初始尺寸、最小尺寸和首次居中。
// 仅在 Windows 桌面端初始化；关闭行为交给系统宿主，避免 Flutter 回调阻塞退出。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_metadata.g.dart';

class AppWindowController {
  bool _initialized = false;

  /// 当前宿主是否为 Windows 桌面端。
  static bool get isWindows => Platform.isWindows;

  /// 初始化标准标题栏窗口，并清除热重启可能遗留的关闭拦截状态。
  Future<void> initialize() async {
    if (!isWindows || _initialized) return;
    _initialized = true;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(false);
    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(960, 640),
      center: true,
      title: AppMetadata.productName,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
