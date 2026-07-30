import 'package:flutter/material.dart';

import '../../core/theme.dart';

class ConstrainedPageList extends StatelessWidget {
  const ConstrainedPageList({
    super.key,
    required this.children,
    this.scrollKey,
    this.controller,
    this.physics,
    this.padding,
  });

  final List<Widget> children;
  final Key? scrollKey;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final horizontal = LumaLayout.pageHorizontalPadding(
      MediaQuery.sizeOf(context).width,
    );
    final resolvedPadding =
        padding ??
        EdgeInsets.fromLTRB(
          horizontal,
          LumaSpacing.xs,
          horizontal,
          LumaLayout.pagePaddingBottom,
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LumaLayout.contentMaxWidth),
        child: SizedBox(
          width: double.infinity,
          child: ListView(
            key: scrollKey,
            controller: controller,
            physics: physics,
            padding: resolvedPadding,
            children: children,
          ),
        ),
      ),
    );
  }
}
