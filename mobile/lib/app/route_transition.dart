// 路由过渡协调器统一等待真实动画结束，供详情刷新和大图解码避开入场帧。
// 页面销毁或动画反向结束时同样释放等待，调用方仍需在继续操作前检查 mounted。
import 'dart:async';

import 'package:flutter/material.dart';

/// 等待当前路由入场动画结束，并让动画最终状态先完整提交一帧。
Future<void> waitForRouteTransition(BuildContext context) async {
  // didChangeDependencies 可能早于新 Route 安装动画控制器，先提交首帧再读取状态。
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  final animation = ModalRoute.of(context)?.animation;
  if (animation != null && animation.status != AnimationStatus.completed) {
    final completer = Completer<void>();
    var hasStarted = animation.status != AnimationStatus.dismissed;
    void completeWhenSettled(AnimationStatus status) {
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.reverse) {
        hasStarted = true;
      }
      if (status != AnimationStatus.completed &&
          !(hasStarted && status == AnimationStatus.dismissed)) {
        return;
      }
      if (!completer.isCompleted) completer.complete();
    }

    animation.addStatusListener(completeWhenSettled);
    completeWhenSettled(animation.status);
    await completer.future;
    animation.removeStatusListener(completeWhenSettled);
  }
  await WidgetsBinding.instance.endOfFrame;
}
