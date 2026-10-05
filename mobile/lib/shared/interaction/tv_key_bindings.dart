// TV 根层按键契约：遥控器 OK/Enter 映射为激活，确认键忽略长按重复，方向键允许重复。
// 只包裹 TV 呈现分支；TextField 编辑态的按键仍由输入框自身处理，Back 统一走 Navigator。
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class TvKeyBindings extends StatelessWidget {
  const TvKeyBindings({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        // 遥控器确认键；includeRepeats 为 false，长按 OK 不会重复激活。
        SingleActivator(LogicalKeyboardKey.select, includeRepeats: false):
            ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
            ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter, includeRepeats: false):
            ActivateIntent(),
        // 前三项只接受按下；重复事件在这里消费，不能冒泡到框架默认激活。
        SingleActivator(LogicalKeyboardKey.select): DoNothingIntent(),
        SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): DoNothingIntent(),
      },
      child: child,
    );
  }
}
