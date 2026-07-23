import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/media_types.dart';

class PlaybackProgress extends StatelessWidget {
  const PlaybackProgress({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    if (item.type != MediaType.video || item.progress <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: LumaSpacing.lg),
      child: Column(
        children: [
          Row(
            children: [
              Text('最近播放进度', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(
                '${(item.progress * 100).round()}%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: LumaSpacing.xs),
          LinearProgressIndicator(
            value: item.progress,
            minHeight: 4,
            borderRadius: BorderRadius.circular(LumaRadii.badge),
          ),
        ],
      ),
    );
  }
}
