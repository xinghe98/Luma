// 统一主操作按钮在窄屏和宽屏下的宽度策略，与 LumaLayout 响应式令牌协作，不持有交互状态。

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 窄视口让操作占满容器，宽视口限制宽度并默认居中。
class AdaptiveActionWidth extends StatelessWidget {
  const AdaptiveActionWidth({
    super.key,
    required this.child,
    this.maxWidth = LumaLayout.actionMaxWidth,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  /// 根据视口决定是否拉伸，避免宽屏表单按钮随页面无限增长。
  @override
  Widget build(BuildContext context) {
    final fillWidth =
        MediaQuery.sizeOf(context).width < LumaLayout.actionWidthBreakpoint;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : maxWidth;
        final constrainedWidth = availableWidth > maxWidth
            ? maxWidth
            : availableWidth;
        return Align(
          alignment: alignment,
          child: SizedBox(
            width: fillWidth ? availableWidth : constrainedWidth,
            child: child,
          ),
        );
      },
    );
  }
}
