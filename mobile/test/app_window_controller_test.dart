// Windows 窗口控制器测试确保系统关闭按钮不再被 Flutter 窗口监听器拦截。
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_window_controller.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  test('窗口控制器不注册关闭事件监听', () {
    expect(AppWindowController(), isNot(isA<WindowListener>()));
  });
}
