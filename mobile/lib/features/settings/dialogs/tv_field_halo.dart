// TV 字段焦点描边：由 TvTextFieldGate 提供焦点状态，供设置和代理弹窗复用。
// 始终保留字段子树及边框空间，避免焦点变化重新挂载输入框或后缀按钮。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 供 TV 弹窗内经 [TvTextFieldGate] 包裹的字段使用；普通端不进入本分支。
class TvFieldHalo extends StatelessWidget {
  /// 根据 [focused] 显示描边，切换时保留输入状态和子控件焦点。
  const TvFieldHalo({super.key, required this.focused, required this.child});

  final Widget child;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: LumaMotion.forContext(context, LumaMotion.fast),
      curve: Curves.easeOutQuart,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LumaRadii.medium),
        border: Border.all(
          color: focused
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: child,
    );
  }
}
