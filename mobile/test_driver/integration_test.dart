// 集成测试宿主驱动：接收设备端结果，并把截图留存在本机 build 目录。
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// 执行隔离集成测试并保存截图；测试或截图写入失败时进程返回失败。
Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  onScreenshot: (name, image, [args]) async {
    final directory = Directory('build/integration_screenshots');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(image, flush: true);
    return true;
  },
);
