// 可聚焦表面统一媒体项目的鼠标、键盘和语义激活状态，并与 Material 焦点系统协作。
// 组件自身只维护悬停与焦点外观，不持有业务状态。
import 'package:flutter/material.dart';

import '../../core/theme.dart';

class LumaFocusableSurface extends StatefulWidget {
  /// 创建可由点击、Enter 或 Space 激活的表面，并显示克制的悬停与焦点轮廓。
  const LumaFocusableSurface({
    super.key,
    required this.label,
    required this.onActivate,
    required this.borderRadius,
    required this.child,
    this.onLongPress,
    this.contentPadding = EdgeInsets.zero,
  });

  final String label;
  final VoidCallback onActivate;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final Widget child;

  /// 在轮廓与内容之间保留固定安全区，悬停或聚焦时不会改变布局。
  final EdgeInsetsGeometry contentPadding;

  @override
  State<LumaFocusableSurface> createState() => _LumaFocusableSurfaceState();
}

class _LumaFocusableSurfaceState extends State<LumaFocusableSurface> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final border = _focused
        ? Border.all(color: colors.primary, width: 2)
        : _hovered
        ? Border.all(color: colors.outlineVariant)
        : null;
    return Semantics(
      button: true,
      label: widget.label,
      child: AnimatedContainer(
        duration: LumaMotion.forContext(context, LumaMotion.fast),
        curve: Curves.easeOutQuart,
        foregroundDecoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: border,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: widget.onActivate,
            onLongPress: widget.onLongPress,
            onFocusChange: (value) => setState(() => _focused = value),
            onHover: (value) => setState(() => _hovered = value),
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            borderRadius: widget.borderRadius,
            child: Padding(padding: widget.contentPadding, child: widget.child),
          ),
        ),
      ),
    );
  }
}
