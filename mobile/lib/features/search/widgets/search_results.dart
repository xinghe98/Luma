import 'package:flutter/material.dart';

import '../../../app/controllers/media_controller.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/media/media_actions.dart';
import '../../../shared/media/responsive_media_grid.dart';
import '../../../shared/states/empty_state.dart';
import '../../../shared/states/error_state.dart';
import '../../../shared/states/skeleton.dart';

/// 搜索结果区，以 sliver 形式嵌入 [CustomScrollView]。
class SearchResults extends StatelessWidget {
  const SearchResults({
    super.key,
    required this.items,
    required this.hasCriteria,
    required this.searchState,
    required this.onOpenMedia,
    required this.onFavorite,
    required this.onClear,
    required this.onSearchRetry,
  });

  final List<MediaItem> items;
  final bool hasCriteria;
  final LoadState searchState;
  final MediaOpenCallback onOpenMedia;
  final ValueChanged<MediaItem> onFavorite;
  final VoidCallback onClear;
  final VoidCallback onSearchRetry;

  @override
  Widget build(BuildContext context) {
    // 单测/预览：无外层滚动时退化为可滚动列表。
    return CustomScrollView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      slivers: buildSlivers(),
    );
  }

  List<Widget> buildSlivers() {
    if (!hasCriteria) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: LumaSpacing.xl),
              const SectionHeader(title: '搜索结果', subtitle: '输入条件后显示'),
              const SizedBox(height: LumaSpacing.md),
              const Expanded(
                child: EmptyState(
                  title: '开始搜索',
                  message: '输入关键词，或选择类型、标签来筛选媒体库。',
                  icon: Icons.search_rounded,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      const SliverToBoxAdapter(child: SizedBox(height: LumaSpacing.xl)),
      SliverToBoxAdapter(
        child: SectionHeader(
          title: '搜索结果',
          subtitle: searchState == LoadState.loading
              ? '搜索中…'
              : '${items.length} 个项目',
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: LumaSpacing.md)),
      ..._bodySlivers(),
    ];
  }

  List<Widget> _bodySlivers() {
    switch (searchState) {
      case LoadState.loading:
        return [const SliverToBoxAdapter(child: MediaGridSkeleton(items: 6))];
      case LoadState.error:
        return [SliverToBoxAdapter(child: ErrorState(onRetry: onSearchRetry))];
      case LoadState.idle:
      case LoadState.ready:
        if (items.isEmpty) {
          return [
            SliverToBoxAdapter(
              child: EmptyState(
                title: '没有找到相关内容',
                message: '换个关键词，或减少筛选条件后再试。',
                icon: Icons.search_off_rounded,
                action: OutlinedButton(
                  onPressed: onClear,
                  child: const Text('清除搜索条件'),
                ),
              ),
            ),
          ];
        }
        return [
          ResponsiveMediaSliverGrid(
            items: items,
            heroTagPrefix: 'search',
            onTap: onOpenMedia,
            onFavorite: onFavorite,
          ),
          const SliverToBoxAdapter(child: SizedBox(height: LumaSpacing.lg)),
        ];
    }
  }
}
