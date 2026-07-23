import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';

class PlayerBottomToolbar extends StatelessWidget {
  const PlayerBottomToolbar({
    super.key,
    required this.controller,
    required this.onRotate,
  });

  final PlayerController controller;
  final VoidCallback? onRotate;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    return Row(
      children: [
        IconButton(
          tooltip: '锁定控制',
          onPressed: () => controller.setLocked(true),
          icon: Icon(Icons.lock_open_rounded, color: extras.onPlayerInk),
        ),
        const Spacer(),
        PopupMenuButton<double>(
          tooltip: '播放速度',
          initialValue: controller.speed,
          onSelected: controller.setSpeed,
          itemBuilder: (_) => [0.5, 1.0, 1.25, 1.5, 2.0]
              .map(
                (speed) =>
                    PopupMenuItem(value: speed, child: Text('${speed}x')),
              )
              .toList(),
          child: Padding(
            padding: const EdgeInsets.all(LumaSpacing.sm),
            child: Text(
              '${controller.speed}x',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: extras.onPlayerInk,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '旋转屏幕',
          onPressed: onRotate,
          icon: Icon(
            Icons.screen_rotation_alt_rounded,
            color: onRotate == null
                ? extras.onPlayerInk.withValues(alpha: 0.38)
                : extras.onPlayerInk,
          ),
        ),
      ],
    );
  }
}
