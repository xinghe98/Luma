import 'package:flutter/material.dart';

import '../../core/theme.dart';

class ConstrainedPageList extends StatelessWidget {
  const ConstrainedPageList({
    super.key,
    required this.children,
    this.scrollKey,
    this.controller,
    this.physics,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 32),
  });

  final List<Widget> children;
  final Key? scrollKey;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LumaLayout.contentMaxWidth),
        child: SizedBox(
          width: double.infinity,
          child: ListView(
            key: scrollKey,
            controller: controller,
            physics: physics,
            padding: padding,
            children: children,
          ),
        ),
      ),
    );
  }
}
