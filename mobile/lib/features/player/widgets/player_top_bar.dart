import 'package:flutter/material.dart';

import '../../../core/theme.dart';

class PlayerTopBar extends StatelessWidget {
  /// 显示片名与返回操作，可选显示收起到应用内小窗的按钮。
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.resolution,
    required this.onBack,
    this.onMinimize,
  });

  final String title;
  final String resolution;
  final VoidCallback onBack;
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    final onInk = context.luma.onPlayerInk;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LumaSpacing.sm,
        vertical: LumaSpacing.xxs,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: Icon(Icons.arrow_back_rounded, color: onInk),
          ),
          const SizedBox(width: LumaSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: onInk),
                ),
                if (resolution.isNotEmpty)
                  Text(
                    resolution,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: onInk.withValues(alpha: 0.72),
                    ),
                  ),
              ],
            ),
          ),
          if (onMinimize != null)
            IconButton(
              tooltip: '小窗播放',
              onPressed: onMinimize,
              icon: Icon(Icons.picture_in_picture_alt_rounded, color: onInk),
            ),
        ],
      ),
    );
  }
}
