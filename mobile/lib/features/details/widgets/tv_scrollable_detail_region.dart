// TV 可聚焦滚动区域：纯文字长区域（简介、演员、文件信息）在遥控器下
// 可获焦，上下键滚动内容；到边界后按键交给默认方向遍历移出焦点。
// 必须放在可滚动的祖先（SingleChildScrollView/CustomScrollView）内部使用。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class TvScrollableDetailRegion extends StatefulWidget {
  const TvScrollableDetailRegion({
    super.key,
    required this.child,
    this.autofocus = false,
  });

  final Widget child;
  final bool autofocus;

  @override
  State<TvScrollableDetailRegion> createState() =>
      _TvScrollableDetailRegionState();
}

class _TvScrollableDetailRegionState extends State<TvScrollableDetailRegion> {
  final _focus = FocusNode(debugLabel: 'tv-detail-scroll-region');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _reveal(bool focused) {
    if (!focused || !_focus.hasPrimaryFocus) return;
    // 焦点通知时资料已完成布局；同步揭示，避免下一帧覆盖用户的翻页。
    Scrollable.ensureVisible(context);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // 子按钮的方向键必须继续走默认遍历，不能被文字区域截获。
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return KeyEventResult.ignored;
    final position = scrollable.position;
    final content = context.findRenderObject();
    if (content == null) return KeyEventResult.ignored;
    final viewport = RenderAbstractViewport.of(content);
    final top = viewport
        .getOffsetToReveal(content, 0)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final bottom = viewport
        .getOffsetToReveal(content, 1)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final down = key == LogicalKeyboardKey.arrowDown;
    // 短资料无需翻页；长资料只滚到自己的上下边缘，随后交接相邻控件。
    if (bottom <= top ||
        (down && position.pixels >= bottom - 0.5) ||
        (!down && position.pixels <= top + 0.5)) {
      return KeyEventResult.ignored;
    }
    final delta = position.viewportDimension * 0.8;
    final target = (position.pixels + (down ? delta : -delta)).clamp(
      top,
      bottom,
    );
    position.jumpTo(target);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      onFocusChange: _reveal,
      child: widget.child,
    );
  }
}
