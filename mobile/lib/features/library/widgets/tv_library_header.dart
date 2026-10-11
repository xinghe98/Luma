// TV 媒体库页头：展示页面传入的筛选快照并回传操作，控制器和加载生命周期留在 LibraryPage。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_types.dart';
import 'library_sort_button.dart';

/// 用局部宽度重排标题操作，筛选始终保持可横向遥控的单行。
class TvLibraryHeader extends StatelessWidget {
  /// 构建媒体库操作区；上传入口仅在图片页提供回调时展示。
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
    this.onUpload,
    this.selectionMode = false,
    this.selectedCount = 0,
    this.onToggleSelect,
    this.onDeleteSelected,
    this.onSelectAll,
    this.onCancelSelection,
    this.deleting = false,
    this.deleteTotal = 0,
    this.deleteDone = 0,
  });

  final String title;
  final bool isVideo;
  final bool showBack;
  final bool hasExtraFilters;
  final bool favoritesOnly;
  final MediaSort sort;
  final VoidCallback? onSearch;

  /// 进入图片上传页；由调用方负责选择、上传及返回后的刷新。
  final VoidCallback? onUpload;
  final VoidCallback onRefresh;

  /// 图片库批量选择态；为 true 时操作行显示删除/全选/退出与计数。
  final bool selectionMode;

  /// 当前已选数量，供操作行按钮与文案展示。
  final int selectedCount;

  /// 进入或退出选择态；普通行与选择行共用。
  final VoidCallback? onToggleSelect;

  /// 触发删除已选图片；为 null 时禁用。
  final VoidCallback? onDeleteSelected;

  /// 全选当前已加载项；为 null 时禁用。
  final VoidCallback? onSelectAll;

  /// 退出选择态；为 null 时禁用。
  final VoidCallback? onCancelSelection;

  /// 是否正在执行批量删除；为 true 时操作行显示进度并只剩停止按钮。
  final bool deleting;

  /// 本批次确认删除的总数；仅在 [deleting] 时使用。
  final int deleteTotal;

  /// 本批次已完成请求的条数；仅在 [deleting] 时使用。
  final int deleteDone;
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
      spacing: LumaSpacing.sm,
      runSpacing: LumaSpacing.xs,
      children: selectionMode
          ? [
              if (deleting)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: LumaIconSize.status,
                      height: LumaIconSize.status,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: LumaSpacing.xs),
                    Text('删除中 $deleteDone/$deleteTotal'),
                  ],
                )
              else ...[
                TextButton.icon(
                  onPressed: onCancelSelection,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('退出选择'),
                ),
                Text('已选 $selectedCount 项'),
                TextButton.icon(
                  onPressed: onSelectAll,
                  icon: const Icon(Icons.select_all_rounded),
                  label: const Text('全选已加载'),
                ),
                FilledButton.icon(
                  onPressed: selectedCount == 0 ? null : onDeleteSelected,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text('删除($selectedCount)'),
                ),
              ],
              if (deleting)
                TextButton.icon(
                  onPressed: onCancelSelection,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('停止剩余'),
                ),
            ]
          : [
              if (!isVideo && onToggleSelect != null)
                TextButton.icon(
                  onPressed: onToggleSelect,
                  icon: const Icon(Icons.checklist_rounded),
                  label: const Text('选择'),
                ),
              if (!isVideo && onUpload != null)
                TextButton.icon(
                  onPressed: onUpload,
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('上传图片'),
                ),
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
        LumaSpacing.md,
        LumaLayout.pagePaddingH,
        LumaSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = LumaTvLayout.compactHeader(
                constraints,
                MediaQuery.textScalerOf(context),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: LumaSpacing.sm),
                    actions,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: LumaSpacing.sm),
                  actions,
                ],
              );
            },
          ),
          const SizedBox(height: LumaSpacing.md),
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
                      horizontal: LumaSpacing.md,
                      vertical: LumaSpacing.sm + 2,
                    ),
                    onSelected: onFavorites,
                  ),
                const SizedBox(width: LumaSpacing.md),
                LibrarySortButton(
                  value: sort,
                  onChanged: onSort,
                  showDuration: isVideo,
                ),
                if (hasExtraFilters) ...[
                  const SizedBox(width: LumaSpacing.md),
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
