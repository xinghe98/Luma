import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';
import 'player_control_button.dart';

class PlayerCenterControls extends StatelessWidget {
  const PlayerCenterControls({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PlayerControlButton(
          icon: Icons.replay_10_rounded,
          tooltip: '后退 10 秒',
          onPressed: () => controller.seekBy(-10),
        ),
        const SizedBox(width: LumaSpacing.lg + LumaSpacing.xxs),
        PlayerControlButton(
          icon: controller.playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          tooltip: controller.playing ? '暂停' : '播放',
          onPressed: controller.togglePlay,
          prominent: true,
        ),
        const SizedBox(width: LumaSpacing.lg + LumaSpacing.xxs),
        PlayerControlButton(
          icon: Icons.forward_10_rounded,
          tooltip: '快进 10 秒',
          onPressed: () => controller.seekBy(10),
        ),
      ],
    );
  }
}
