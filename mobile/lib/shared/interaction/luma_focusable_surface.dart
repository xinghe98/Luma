// 可聚焦表面统一媒体项目的鼠标、键盘和语义激活状态，并与 Material 焦点系统协作。
// 组件自身只维护悬停与焦点外观，不持有业务状态；带 focusId 时向最近的
// TvFocusCollection 注册焦点节点，节点随本组件卸载自动注销。
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'tv_focus_collection.dart';

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
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.focusId,
    this.focusBorderWidth = 2,
    this.paintFocusBorder = true,
    this.paintHoverFill = true,
  });

  final String label;
  final VoidCallback onActivate;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final Widget child;

  /// 在轮廓与内容之间保留固定安全区，悬停或聚焦时不会改变布局。
  final EdgeInsetsGeometry contentPadding;

  /// 外部提供的焦点节点；为空且需要注册集合时由组件内部创建并随组件释放。
  final FocusNode? focusNode;

  /// 是否挂载即请求焦点；TV 页面用它指定首个主动作/卡片。
  final bool autofocus;

  /// 焦点变化回调；组件内部的描边状态与其独立维护。
  final ValueChanged<bool>? onFocusChange;

  /// TV 列表内的稳定身份；非空时向最近的 TvFocusCollection 注册。
  final String? focusId;

  /// 聚焦描边宽度；TV 使用 3dp 保证观看距离可见，普通端保持 2dp。
  /// TV 宽度会在内容外侧留出同等槽位，描边不压文字。
  final double focusBorderWidth;

  /// 为 false 时不在整张卡片上描边，子组件用 [LumaFocusMark] 只标出封面。
  final bool paintFocusBorder;

  /// 为 false 时悬停与按下不给整块表面铺底色，交给封面用 [LumaCoverLift] 自行表达。
  final bool paintHoverFill;

  @override
  State<LumaFocusableSurface> createState() => _LumaFocusableSurfaceState();
}

class _LumaFocusableSurfaceState extends State<LumaFocusableSurface> {
  FocusNode? _ownedNode;
  TvFocusCollectionScope? _collection;
  String? _registeredId;
  FocusNode? _registeredNode;

  FocusNode get _effectiveNode =>
      widget.focusNode ?? (_ownedNode ??= FocusNode());
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncCollectionRegistration();
  }

  @override
  void didUpdateWidget(LumaFocusableSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusId != widget.focusId ||
        oldWidget.focusNode != widget.focusNode) {
      _syncCollectionRegistration();
    }
  }

  /// 把 focusId 注册进最近的外层集合；集合、ID 或节点变化时先注销旧记录。
  void _syncCollectionRegistration() {
    final scope = TvFocusCollectionScope.maybeOf(context);
    final id = widget.focusId;
    if (!identical(scope, _collection) ||
        _registeredId != id ||
        (_registeredNode != null && _registeredNode != _effectiveNode)) {
      _unregisterFromCollection();
      _collection = scope;
    }
    if (scope != null && id != null && _registeredId == null) {
      scope.registerFocusItem(id, _effectiveNode);
      _registeredId = id;
      _registeredNode = _effectiveNode;
    }
  }

  void _unregisterFromCollection() {
    final id = _registeredId;
    if (_collection != null && id != null) {
      _collection!.unregisterFocusItem(id, _registeredNode!);
    }
    _collection = null;
    _registeredId = null;
    _registeredNode = null;
  }

  void _handleFocusChange(bool value) {
    setState(() => _focused = value);
    widget.onFocusChange?.call(value);
  }

  @override
  void dispose() {
    _unregisterFromCollection();
    _ownedNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // 槽位放在焦点节点内部。放在外面时，揭示只会对准内层，3dp 白边会探出视口。
    final strokeGutter =
        widget.paintFocusBorder &&
            widget.focusBorderWidth >= LumaTvLayout.focusStroke
        ? EdgeInsets.all(widget.focusBorderWidth)
        : EdgeInsets.zero;
    final interactive = Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        focusNode: widget.focusNode ?? _ownedNode,
        autofocus: widget.autofocus,
        onTap: widget.onActivate,
        onLongPress: widget.onLongPress,
        onFocusChange: _handleFocusChange,
        onHover: (value) => setState(() => _hovered = value),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        borderRadius: widget.borderRadius,
        child: LumaFocusMark(
          focused: _focused,
          hovered: _hovered || _pressed,
          child: Padding(
            padding: widget.contentPadding.add(strokeGutter),
            child: widget.child,
          ),
        ),
      ),
    );
    if (!widget.paintFocusBorder) {
      return Semantics(button: true, label: widget.label, child: interactive);
    }
    // 悬停不画描边，只保留键盘焦点轮廓；整卡描边会把标题也框进去，显得生硬。
    final border = _focused
        ? Border.all(
            color: widget.focusBorderWidth >= LumaTvLayout.focusStroke
                ? colors.onSurface
                : colors.primary,
            width: widget.focusBorderWidth,
          )
        : null;
    // 背景画在内容后面，封面不会被染色，只有内距框和文字区域变色。
    final fill = !widget.paintHoverFill
        ? null
        : _pressed
        ? colors.onSurface.withValues(alpha: LumaOpacity.pressed)
        : _hovered
        ? colors.onSurface.withValues(alpha: LumaOpacity.hover)
        : null;
    return Semantics(
      button: true,
      label: widget.label,
      child: AnimatedContainer(
        duration: LumaMotion.forContext(context, LumaMotion.fast),
        curve: Curves.easeOutQuart,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          color: fill,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: border,
        ),
        child: interactive,
      ),
    );
  }
}

/// 把当前表面的焦点与悬停状态传给封面等局部装饰，不额外占用布局。
class LumaFocusMark extends InheritedWidget {
  const LumaFocusMark({
    super.key,
    required this.focused,
    this.hovered = false,
    required super.child,
  });

  final bool focused;

  /// 指针悬停或按下中；封面据此浮起，触摸端只在按下瞬间生效。
  final bool hovered;

  /// 最近一层可聚焦表面是否持有焦点；没有表面时视为未聚焦。
  static bool focusedOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LumaFocusMark>()?.focused ??
      false;

  /// 最近一层可聚焦表面是否处于悬停或按下；没有表面时为 false。
  static bool hoveredOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LumaFocusMark>()?.hovered ??
      false;

  @override
  bool updateShouldNotify(LumaFocusMark oldWidget) =>
      focused != oldWidget.focused || hovered != oldWidget.hovered;
}

/// 普通端封面的悬停反馈：整张封面轻微上浮并加柔和投影，标题不动、不加描边。
/// 只改位移和阴影，不染色封面，浅色与深色图片上都同样克制。
class LumaCoverLift extends StatelessWidget {
  const LumaCoverLift({
    super.key,
    required this.borderRadius,
    required this.child,
  });

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lifted = LumaFocusMark.hoveredOf(context);
    return AnimatedContainer(
      duration: LumaMotion.forContext(context, LumaMotion.fast),
      curve: Curves.easeOutQuart,
      transform: Matrix4.translationValues(
        0,
        lifted ? -_coverLiftOffset : 0,
        0,
      ),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: LumaColors.shadow.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: child,
    );
  }
}

const _coverLiftOffset = 3.0;

/// 只沿封面绘制电视焦点，标题留在描边外面，避免笔画切进文字。
class TvArtworkFocus extends StatelessWidget {
  const TvArtworkFocus({
    super.key,
    required this.borderRadius,
    required this.child,
  });

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final focused = LumaFocusMark.focusedOf(context);
    final color = Theme.of(context).colorScheme.onSurface;
    const stroke = LumaTvLayout.focusStroke;
    return AnimatedContainer(
      duration: LumaMotion.forContext(context, LumaMotion.fast),
      curve: Curves.easeOutQuart,
      padding: const EdgeInsets.all(stroke),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: focused
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.24),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: focused ? color : const Color(0x00000000),
          width: stroke,
        ),
      ),
      child: ClipRRect(
        borderRadius: _insetRadius(borderRadius, stroke),
        child: child,
      ),
    );
  }
}

/// 封面圆角随描边槽内收，避免圆角处露出一条未裁切的图片边。
BorderRadius _insetRadius(BorderRadius radius, double inset) {
  Radius deflate(Radius corner) => Radius.elliptical(
    (corner.x - inset).clamp(0, double.infinity),
    (corner.y - inset).clamp(0, double.infinity),
  );
  return BorderRadius.only(
    topLeft: deflate(radius.topLeft),
    topRight: deflate(radius.topRight),
    bottomLeft: deflate(radius.bottomLeft),
    bottomRight: deflate(radius.bottomRight),
  );
}
