import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 统一的浅色容器卡片，替代各处重复的
/// `Card(elevation: 0, color: surfaceContainer)` 与 `DecoratedBox` 写法。
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LumaSpacing.md),
    this.radius = LumaRadii.medium,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Material(
      color:
          Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
