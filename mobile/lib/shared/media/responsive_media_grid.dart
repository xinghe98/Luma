import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import 'media_actions.dart';
import 'media_card.dart';

class ResponsiveMediaGrid extends StatelessWidget {
  const ResponsiveMediaGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.onFavorite,
    this.physics = const NeverScrollableScrollPhysics(),
    this.shrinkWrap = true,
    this.heroTagPrefix,
  });

  final List<MediaItem> items;
  final MediaOpenCallback onTap;
  final ValueChanged<MediaItem>? onFavorite;
  final ScrollPhysics physics;

  /// 嵌在外层 ListView 时为 true；作为主滚动体时应为 false 以启用懒构建。
  final bool shrinkWrap;

  /// 传入后为每张卡片封面启用 Hero 动画，tag 形如 `'$heroTagPrefix-{id}'`，
  /// 需保证同屏内各网格使用不同前缀。
  final String? heroTagPrefix;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return GridView.builder(
          shrinkWrap: shrinkWrap,
          physics: physics,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          gridDelegate: sliverGridDelegateForWidth(width),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final heroTag = heroTagPrefix == null
                ? null
                : '$heroTagPrefix-${item.id}';
            return MediaCard(
              key: ValueKey(item.id),
              item: item,
              heroTag: heroTag,
              onTap: () => onTap(item, heroTag: heroTag),
              onFavorite: onFavorite == null ? null : () => onFavorite!(item),
            );
          },
        );
      },
    );
  }

  static SliverGridDelegate sliverGridDelegateForWidth(double width) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: LumaLayout.gridColumns(width),
      mainAxisSpacing: LumaSpacing.lg,
      crossAxisSpacing: LumaSpacing.md,
      childAspectRatio: LumaLayout.mediaCardAspectRatio(width),
    );
  }
}

/// 用于 CustomScrollView 的懒加载媒体网格，避免 shrinkWrap 一次构建全部子项。
class ResponsiveMediaSliverGrid extends StatelessWidget {
  const ResponsiveMediaSliverGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.onFavorite,
    this.heroTagPrefix,
  });

  final List<MediaItem> items;
  final MediaOpenCallback onTap;
  final ValueChanged<MediaItem>? onFavorite;
  final String? heroTagPrefix;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const _ResponsiveMediaSliverGridDelegate(),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          final heroTag = heroTagPrefix == null
              ? null
              : '$heroTagPrefix-${item.id}';
          return MediaCard(
            key: ValueKey(item.id),
            item: item,
            heroTag: heroTag,
            onTap: () => onTap(item, heroTag: heroTag),
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

/// 在 RenderSliver 布局阶段按宽度选择列数，避免滚动偏移变化时重建网格。
class _ResponsiveMediaSliverGridDelegate extends SliverGridDelegate {
  const _ResponsiveMediaSliverGridDelegate();

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) =>
      ResponsiveMediaGrid.sliverGridDelegateForWidth(
        constraints.crossAxisExtent,
      ).getLayout(constraints);

  @override
  bool shouldRelayout(_ResponsiveMediaSliverGridDelegate oldDelegate) => false;
}
