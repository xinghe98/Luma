import 'package:flutter/material.dart';

/// 让可滚动页面复用一致的顶部双击回顶交互，不干扰 AppBar 的操作按钮。
class ScrollToTopAppBarTitle extends StatelessWidget {
  const ScrollToTopAppBarTitle({
    super.key,
    required this.title,
    required this.controller,
  });

  final String title;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onDoubleTap: () {
      if (!controller.hasClients || controller.offset <= 0) return;
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    },
    child: SizedBox(
      width: double.infinity,
      child: Align(alignment: Alignment.centerLeft, child: Text(title)),
    ),
  );
}
