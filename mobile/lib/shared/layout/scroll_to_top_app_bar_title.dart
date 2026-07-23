import 'package:flutter/material.dart';

/// 让可滚动页面复用一致的顶部双击回顶交互，不干扰 AppBar 的操作按钮。
class ScrollToTopAppBarTitle extends StatelessWidget {
  const ScrollToTopAppBarTitle({
    super.key,
    required this.title,
    this.controller,
    this.onScrollToTop,
  }) : assert(controller != null || onScrollToTop != null);

  final String title;
  final ScrollController? controller;

  /// 供拥有多个内部滚动列表的页面将双击操作转发到当前列表。
  final VoidCallback? onScrollToTop;

  void _scrollToTop() {
    final callback = onScrollToTop;
    if (callback != null) {
      callback();
      return;
    }
    final scrollController = controller!;
    if (!scrollController.hasClients || scrollController.offset <= 0) return;
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onDoubleTap: _scrollToTop,
    child: SizedBox(
      width: double.infinity,
      child: Align(alignment: Alignment.centerLeft, child: Text(title)),
    ),
  );
}
