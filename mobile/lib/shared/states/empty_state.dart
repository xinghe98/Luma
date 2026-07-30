import 'package:flutter/material.dart';

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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(LumaRadii.large),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(LumaSpacing.md),
                  child: Icon(
                    icon,
                    size: LumaIconSize.emptyState,
                    color: scheme.primary,
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
