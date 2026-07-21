import 'package:flutter/material.dart';

import '../../../shared/formatters/duration_formatter.dart';
import '../player_controller.dart';

class PlayerTimeline extends StatelessWidget {
  const PlayerTimeline({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final durationMs = controller.duration.inMilliseconds.toDouble();
    final positionMs = controller.position.inMilliseconds.clamp(
      0,
      controller.duration.inMilliseconds,
    );
    return Row(
      children: [
        Text(
          formatDuration(controller.position),
          style: const TextStyle(color: Colors.white),
        ),
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
        Text(
          formatDuration(controller.duration),
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}
