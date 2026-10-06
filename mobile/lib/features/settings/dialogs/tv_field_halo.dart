// TV 字段焦点描边：由 TvTextFieldGate 提供焦点状态，供连接与设置弹窗复用。
// 保留字段子树及边框空间，获焦后滚入视口；卸载后取消待执行的可见性更新。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 在浏览焦点进入时显示 3dp 描边并滚动到字段，不接管字段编辑和返回逻辑。
class TvFieldHalo extends StatefulWidget {
  /// 根据 [focused] 显示描边，切换时保留输入状态和子控件焦点。
  const TvFieldHalo({super.key, required this.focused, required this.child});

  final Widget child;
  final bool focused;

  @override
  State<TvFieldHalo> createState() => _TvFieldHaloState();
}

class _TvFieldHaloState extends State<TvFieldHalo> {
  @override
  void initState() {
    super.initState();
    if (widget.focused) _reveal();
  }

  @override
  void didUpdateWidget(TvFieldHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused && !oldWidget.focused) _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.focused) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: LumaMotion.forContext(context, LumaMotion.fast),
      curve: Curves.easeOutQuart,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LumaRadii.medium),
        border: Border.all(
          color: widget.focused
              ? Theme.of(context).colorScheme.onSurface
              : Colors.transparent,
          width: LumaTvLayout.focusStroke,
        ),
      ),
      child: widget.child,
    );
  }
}
