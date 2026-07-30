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
