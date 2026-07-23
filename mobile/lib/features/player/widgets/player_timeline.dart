import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../player_controller.dart';

class PlayerTimeline extends StatelessWidget {
  const PlayerTimeline({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final onInk = context.luma.onPlayerInk;
    final durationMs = controller.duration.inMilliseconds.toDouble();
    final positionMs = controller.position.inMilliseconds.clamp(
      0,
      controller.duration.inMilliseconds,
    );
    final timeStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: onInk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Text(formatDuration(controller.position), style: timeStyle),
        Expanded(
          child: Slider(
            value: durationMs <= 0 ? 0 : positionMs.toDouble(),
            max: durationMs <= 0 ? 1 : durationMs,
            onChangeStart: (_) => controller.beginScrub(),
            onChanged: (value) =>
                controller.updateScrub(Duration(milliseconds: value.round())),
            onChangeEnd: (_) => controller.commitScrub(),
          ),
        ),
        Text(formatDuration(controller.duration), style: timeStyle),
      ],
    );
  }
}
