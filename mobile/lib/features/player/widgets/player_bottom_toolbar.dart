import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';

class PlayerBottomToolbar extends StatelessWidget {
  /// 构建平台化底栏；桌面显示音量和全屏，移动端保留锁定与旋转。
  const PlayerBottomToolbar({
    super.key,
    required this.controller,
    required this.onRotate,
    this.isDesktop = false,
    this.isFullScreen = false,
    this.onToggleFullScreen,
  });

  final PlayerController controller;
  final VoidCallback? onRotate;
  final bool isDesktop;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    if (isDesktop) {
      return Row(
        children: [
          IconButton(
            tooltip: controller.muted ? '取消静音' : '静音',
            onPressed: controller.toggleMute,
            icon: Icon(
              controller.muted || controller.volume <= 0
                  ? Icons.volume_off_rounded
                  : controller.volume < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
              color: extras.onPlayerInk,
            ),
          ),
          SizedBox(
            width: 132,
            child: Slider(
              value: controller.volume,
              onChanged: controller.setLocalVolume,
              semanticFormatterCallback: (value) =>
                  '音量 ${(value * 100).round()}%',
            ),
          ),
          const Spacer(),
          _PlaybackSpeedMenu(controller: controller),
          IconButton(
            tooltip: isFullScreen ? '退出全屏' : '进入全屏',
            onPressed: onToggleFullScreen,
            icon: Icon(
              isFullScreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: extras.onPlayerInk,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        IconButton(
          tooltip: '锁定控制',
          onPressed: () => controller.setLocked(true),
          icon: Icon(Icons.lock_open_rounded, color: extras.onPlayerInk),
        ),
        const Spacer(),
        _PlaybackSpeedMenu(controller: controller),
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

class _PlaybackSpeedMenu extends StatelessWidget {
  const _PlaybackSpeedMenu({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    return PopupMenuButton<double>(
      tooltip: '播放速度',
      initialValue: controller.speed,
      onSelected: controller.setSpeed,
      itemBuilder: (_) => [0.5, 1.0, 1.25, 1.5, 2.0]
          .map((speed) => PopupMenuItem(value: speed, child: Text('${speed}x')))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.all(LumaSpacing.sm),
        child: Text(
          '${controller.speed}x',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: extras.onPlayerInk),
        ),
      ),
    );
  }
}
