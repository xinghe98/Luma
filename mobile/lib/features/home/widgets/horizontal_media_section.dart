import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/media/media_actions.dart';
import '../../../shared/media/media_card.dart';

class HorizontalMediaSection extends StatelessWidget {
  const HorizontalMediaSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heroPrefix,
    required this.items,
    required this.onOpenMedia,
    required this.onFavorite,
  });

  final String title;
  final String subtitle;

  /// Hero tag 前缀，保证同屏多个分区之间 tag 不重复。
  final String heroPrefix;
  final List<MediaItem> items;
  final MediaOpenCallback onOpenMedia;
  final ValueChanged<MediaItem> onFavorite;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SectionHeader(title: title, subtitle: subtitle),
          ),
          const SizedBox(height: LumaSpacing.md),
          SizedBox(
            height: LumaLayout.horizontalCardHeight,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: LumaSpacing.md),
              itemBuilder: (context, index) {
                final item = items[index];
                final heroTag = '$heroPrefix-${item.id}';
                return SizedBox(
                  width: LumaLayout.horizontalCardWidth,
                  child: MediaCard(
                    item: item,
                    compact: true,
                    heroTag: heroTag,
                    onTap: () => onOpenMedia(item, heroTag: heroTag),
                    onFavorite: () => onFavorite(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
