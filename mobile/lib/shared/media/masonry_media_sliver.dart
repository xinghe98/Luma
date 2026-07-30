import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import 'masonry_media_tile.dart';
import 'media_actions.dart';

/// Pinterest 式多列瀑布流 sliver，按 [MediaItem.aspectRatio] 分配到最短列。
class MasonryMediaSliver extends StatelessWidget {
  const MasonryMediaSliver({
    super.key,
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.onFavorite,
    this.spacing = LumaSpacing.xs,
  });

  final List<MediaItem> items;
  final MediaOpenCallback onTap;
  final MediaOpenCallback? onLongPress;
  final ValueChanged<MediaItem>? onFavorite;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SliverMasonryGrid(
      gridDelegate: const _ResponsiveMasonryGridDelegate(),
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          final heroTag = 'photos-${item.id}';
          return MasonryMediaTile(
            key: ValueKey(item.id),
            item: item,
            heroTag: heroTag,
            onTap: () => onTap(item, heroTag: heroTag),
            onLongPress: onLongPress == null
                ? null
                : () => onLongPress!(item, heroTag: heroTag),
            onFavorite: onFavorite == null ? null : () => onFavorite!(item),
          );
        },
        childCount: items.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
      ),
    );
  }
}

/// 与普通媒体网格共用断点，但直接在 RenderSliver 布局阶段选列数。
/// 这避免了 SliverLayoutBuilder 因 scrollOffset 改变而在每帧重建子树。
class _ResponsiveMasonryGridDelegate extends SliverSimpleGridDelegate {
  const _ResponsiveMasonryGridDelegate();

  @override
  int getCrossAxisCount(
    SliverConstraints constraints,
    double crossAxisSpacing,
  ) => LumaLayout.gridColumns(constraints.crossAxisExtent);

  @override
  bool shouldRelayout(_ResponsiveMasonryGridDelegate oldDelegate) => false;
}
