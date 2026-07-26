import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../connection_controller.dart';

class ConnectionNotice extends StatelessWidget {
  const ConnectionNotice({
    super.key,
    required this.phase,
    required this.message,
  });

  final ConnectionPhase phase;
  final String message;

  @override
  Widget build(BuildContext context) {
    final success = phase == ConnectionPhase.success;
    final failure = phase == ConnectionPhase.failure;
    final color = success
        ? context.luma.success
        : failure
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: LumaSpacing.sm),
        child: Row(
          children: [
            Icon(
              success
                  ? Icons.check_circle_outline_rounded
                  : failure
                  ? Icons.error_outline_rounded
                  : Icons.sync_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: LumaSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
