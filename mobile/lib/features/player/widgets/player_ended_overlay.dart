// 播放结束态覆盖层：居中展示「已播放完毕」与重新播放、返回操作。
// 由播放器场景在 PlayerController.completed 时替换中央控件挂载；
// 纯展示组件，不持有状态，重播与退出通过回调交还调用方。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';

/// 播放到结尾后的操作层；[onExit] 负责返回上一页。
class PlayerEndedOverlay extends StatelessWidget {
  /// 构建结束态覆盖层；[television] 为 true 时重播按钮自动获焦。
  const PlayerEndedOverlay({
    super.key,
    required this.controller,
    required this.onExit,
    this.television = false,
  });

  final PlayerController controller;
  final VoidCallback onExit;
  final bool television;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.replay_rounded,
            size: 48,
            color: extras.onPlayerInk,
          ),
          const SizedBox(height: LumaSpacing.sm),
          Text(
            '已播放完毕',
            style: textTheme.titleLarge?.copyWith(color: extras.onPlayerInk),
          ),
          const SizedBox(height: LumaSpacing.lg),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                autofocus: television,
                onPressed: controller.replay,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('重新播放'),
              ),
              const SizedBox(width: LumaSpacing.md),
              OutlinedButton(onPressed: onExit, child: const Text('返回')),
            ],
          ),
        ],
      ),
    );
  }
}
