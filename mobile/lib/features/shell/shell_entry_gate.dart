// 底部导航首入场预算协调器，让媒体请求和屏外构建避开胶囊切换动画。
// 它只等待当前主题的导航动效时长，不持有页面状态或改变路由生命周期。
import 'package:flutter/widgets.dart';

import '../../core/theme.dart';

/// 等待底部导航动画完成；关闭系统动画时仅让目标页面提交首帧。
Future<void> waitForShellEntrySettle(BuildContext context) async {
  final duration = LumaMotion.forContext(context, LumaMotion.navigation);
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted || duration == Duration.zero) return;
  await Future<void>.delayed(duration);
  if (!context.mounted) return;
  await WidgetsBinding.instance.endOfFrame;
}

/// 标记电视壳层这次是直接进入内容，而不是停在展开的导航上。
class TvShellEntry extends InheritedWidget {
  const TvShellEntry({
    super.key,
    required this.focusContent,
    required super.child,
  });

  /// 为 true 时影视库应把焦点交给第一张可选择的卡片。
  final bool focusContent;

  /// 没有壳层标记时返回 false，普通页面和测试不会抢焦点。
  static bool focusContentOf(BuildContext context) {
    final entry = context.dependOnInheritedWidgetOfExactType<TvShellEntry>();
    return entry?.focusContent ?? false;
  }

  @override
  bool updateShouldNotify(TvShellEntry oldWidget) =>
      focusContent != oldWidget.focusContent;
}
