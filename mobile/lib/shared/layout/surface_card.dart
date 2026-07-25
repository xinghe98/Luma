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
    this.outlined = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(radius);
    final color = Theme.of(context).cardTheme.color ?? scheme.surfaceContainer;

    final content = Padding(padding: padding, child: child);

    return Material(
      color: color,
      borderRadius: borderRadius,
      shape: outlined
          ? RoundedRectangleBorder(
              borderRadius: borderRadius,
              side: BorderSide(color: scheme.outlineVariant.withAlpha(90)),
            )
          : null,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, borderRadius: borderRadius, child: content),
    );
  }
}
