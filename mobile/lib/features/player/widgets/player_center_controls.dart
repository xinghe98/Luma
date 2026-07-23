import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';

class PlayerCenterControls extends StatelessWidget {
  const PlayerCenterControls({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlButton(
          icon: Icons.replay_10_rounded,
          tooltip: '后退 10 秒',
          onPressed: () => controller.seekBy(-10),
        ),
        const SizedBox(width: LumaSpacing.lg + LumaSpacing.xxs),
        IconButton.filled(
          tooltip: controller.playing ? '暂停' : '播放',
          style: IconButton.styleFrom(
            backgroundColor: extras.onPlayerInk,
            foregroundColor: extras.playerInk,
            minimumSize: const Size.square(64),
          ),
          onPressed: controller.togglePlay,
          iconSize: 36,
          icon: Icon(
            controller.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
        ),
        const SizedBox(width: LumaSpacing.lg + LumaSpacing.xxs),
        _ControlButton(
          icon: Icons.forward_10_rounded,
          tooltip: '快进 10 秒',
          onPressed: () => controller.seekBy(10),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    return IconButton(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: extras.playerInk.withAlpha(90),
        foregroundColor: extras.onPlayerInk,
        minimumSize: const Size.square(LumaLayout.minTapTarget + 2),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 30),
    );
  }
}
