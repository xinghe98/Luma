import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/media_types.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/layout/surface_card.dart';

class MediaMetadata extends StatelessWidget {
  const MediaMetadata({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '媒体信息'),
        const SizedBox(height: LumaSpacing.sm),
        Wrap(
          spacing: LumaSpacing.sm,
          runSpacing: LumaSpacing.sm,
          children: [
            if (item.type == MediaType.video)
              _InfoTile(label: '时长', value: formatDuration(item.duration)),
            _InfoTile(label: '分辨率', value: item.resolution),
            _InfoTile(label: '格式', value: item.format),
            _InfoTile(label: '文件大小', value: item.fileSize),
          ],
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: SurfaceCard(
        padding: const EdgeInsets.all(LumaSpacing.sm),
        radius: LumaRadii.small,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
