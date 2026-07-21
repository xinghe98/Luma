import 'package:flutter/material.dart';

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
    return Row(
      children: [
        IconButton(
          tooltip: '锁定控制',
          onPressed: () => controller.setLocked(true),
          icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
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
            padding: const EdgeInsets.all(12),
            child: Text(
              '${controller.speed}x',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '旋转屏幕',
          onPressed: onRotate,
          icon: Icon(
            Icons.screen_rotation_alt_rounded,
            color: onRotate == null ? Colors.white38 : Colors.white,
          ),
        ),
      ],
    );
  }
}
