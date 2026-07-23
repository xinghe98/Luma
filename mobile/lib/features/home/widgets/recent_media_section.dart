import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/media/media_actions.dart';
import '../../../shared/media/responsive_media_grid.dart';

class RecentMediaSection extends StatelessWidget {
  const RecentMediaSection({
    super.key,
    required this.items,
    required this.onOpenMedia,
    required this.onFavorite,
  });

  final List<MediaItem> items;
  final MediaOpenCallback onOpenMedia;
  final ValueChanged<MediaItem> onFavorite;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LumaLayout.contentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            LumaLayout.pagePaddingH,
            LumaSpacing.sm,
            LumaLayout.pagePaddingH,
            LumaSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: '最近添加', subtitle: '服务器里新出现的内容'),
              const SizedBox(height: LumaSpacing.md),
              ResponsiveMediaGrid(
                items: items,
                heroTagPrefix: 'recent',
                onTap: onOpenMedia,
                onFavorite: onFavorite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
