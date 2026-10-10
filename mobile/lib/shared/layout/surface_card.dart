import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 统一的浅色容器卡片，替代各处重复的
/// `Card(elevation: 0, color: surfaceContainer)` 与 `DecoratedBox` 写法。
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LumaSpacing.md),
    this.radius = LumaRadii.large,
    this.onTap,
    this.outlined = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool outlined;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(radius);
    final resolvedColor = color ?? scheme.surfaceContainer;

    final content = Padding(padding: padding, child: child);

    return Material(
      color: resolvedColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: outlined ? scheme.outline : scheme.outlineVariant,
        ),
      ),
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, borderRadius: borderRadius, child: content),
    );
  }
}
