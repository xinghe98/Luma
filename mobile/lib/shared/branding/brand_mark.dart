import 'package:flutter/material.dart';

import '../../core/theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/luma-symbol-color-transparent.png',
          width: compact ? 34 : 52,
          height: compact ? 34 : 52,
        ),
        if (!compact) ...[
          const SizedBox(width: LumaSpacing.sm),
          Text('轻影', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(width: 6),
          Text(
            'Luma',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}
