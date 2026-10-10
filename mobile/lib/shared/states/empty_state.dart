import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.video_library_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: LumaSpacing.xxl + LumaSpacing.lg,
        horizontal: LumaSpacing.lg,
      ),
      child: Center(
        child: _MaxWidthBox(
          maxWidth: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(LumaRadii.large),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(LumaSpacing.md),
                  child: Icon(
                    icon,
                    size: LumaIconSize.emptyState,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: LumaSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: LumaSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: LumaSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 限宽盒：与 ConstrainedBox 相同，但计算固有高度时也按限宽测量文字。
/// SliverFillRemaining 依赖固有高度，ConstrainedBox 会按整行宽度测量而低估换行高度。
class _MaxWidthBox extends ConstrainedBox {
  _MaxWidthBox({required double maxWidth, required super.child})
    : super(constraints: BoxConstraints(maxWidth: maxWidth));

  @override
  RenderConstrainedBox createRenderObject(BuildContext context) =>
      _RenderMaxWidthBox(additionalConstraints: constraints);
}

class _RenderMaxWidthBox extends RenderConstrainedBox {
  _RenderMaxWidthBox({required super.additionalConstraints});

  double _clamp(double width) => width < additionalConstraints.maxWidth
      ? width
      : additionalConstraints.maxWidth;

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(_clamp(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(_clamp(width));
}
