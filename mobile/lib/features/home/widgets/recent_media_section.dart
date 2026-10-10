import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/media/media_actions.dart';
import '../../../shared/media/responsive_media_grid.dart';
import 'home_layout.dart';
import 'horizontal_media_section.dart';

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

  /// TV 最近添加按横向货架浏览，普通端继续使用响应式网格。
  @override
  Widget build(BuildContext context) {
    final isTelevision = AppScope.of(context).deviceProfile.isTelevision;
    if (isTelevision) {
      return HorizontalMediaSection(
        title: '最近添加',
        heroPrefix: 'recent',
        items: items,
        onOpenMedia: onOpenMedia,
        onFavorite: onFavorite,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = HomeLayout.sideInset(constraints.maxWidth);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            inset,
            LumaSpacing.sm,
            inset,
            LumaSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: '最近添加'),
              const SizedBox(height: LumaSpacing.md),
              ResponsiveMediaGrid(
                items: items,
                heroTagPrefix: 'recent',
                onTap: onOpenMedia,
                onFavorite: onFavorite,
              ),
            ],
          ),
        );
      },
    );
  }
}
