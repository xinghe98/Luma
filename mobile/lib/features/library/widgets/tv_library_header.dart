// TV 媒体库页头：展示页面传入的筛选快照并回传操作，控制器和加载生命周期留在 LibraryPage。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_types.dart';

/// 用局部宽度重排标题操作，筛选始终保持可横向遥控的单行。
class TvLibraryHeader extends StatelessWidget {
  const TvLibraryHeader({
    super.key,
    required this.title,
    required this.isVideo,
    required this.showBack,
    required this.hasExtraFilters,
    required this.favoritesOnly,
    required this.sort,
    required this.onRefresh,
    required this.onFilters,
    required this.onFavorites,
    required this.onSort,
    required this.onClear,
    this.onSearch,
  });

  final String title;
  final bool isVideo;
  final bool showBack;
  final bool hasExtraFilters;
  final bool favoritesOnly;
  final MediaSort sort;
  final VoidCallback? onSearch;
  final VoidCallback onRefresh;
  final VoidCallback onFilters;
  final ValueChanged<bool> onFavorites;
  final ValueChanged<MediaSort> onSort;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      children: [
        if (showBack) const BackButton(),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineLarge),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        if (onSearch != null)
          Tooltip(
            message: '搜索',
            child: TextButton.icon(
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
              label: const Text('搜索'),
            ),
          ),
        Tooltip(
          message: '刷新',
          child: TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('刷新'),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LumaLayout.pagePaddingH,
        16,
        LumaLayout.pagePaddingH,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth <
                  640 * MediaQuery.textScalerOf(context).scale(18) / 18;
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 12), actions],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (isVideo)
                  OutlinedButton.icon(
                    onPressed: onFilters,
                    icon: const Icon(Icons.tune_rounded),
                    label: Text(hasExtraFilters ? '筛选已启用' : '筛选'),
                  )
                else
                  FilterChip(
                    label: const Text('仅显示收藏'),
                    selected: favoritesOnly,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    onSelected: onFavorites,
                  ),
                const SizedBox(width: 16),
                PopupMenuButton<MediaSort>(
                  tooltip: '排序',
                  initialValue: sort,
                  onSelected: onSort,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: MediaSort.newest,
                      child: Text('最近添加'),
                    ),
                    const PopupMenuItem(
                      value: MediaSort.title,
                      child: Text('标题名称'),
                    ),
                    if (isVideo)
                      const PopupMenuItem(
                        value: MediaSort.duration,
                        child: Text('视频时长'),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort_rounded),
                        const SizedBox(width: 10),
                        Text(switch (sort) {
                          MediaSort.newest => '最近添加',
                          MediaSort.title => '标题名称',
                          MediaSort.duration => '视频时长',
                        }),
                        const Icon(Icons.arrow_drop_down_rounded),
                      ],
                    ),
                  ),
                ),
                if (hasExtraFilters) ...[
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('清除筛选'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
