import 'package:flutter/material.dart';

import '../../core/theme.dart';

class MediaBadge extends StatelessWidget {
  const MediaBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: extras.badgeScrim,
        borderRadius: BorderRadius.circular(LumaRadii.badge),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LumaSpacing.xs,
          vertical: LumaSpacing.xxs,
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: extras.onPlayerInk),
        ),
      ),
    );
  }
}
