// 图片库批量选择操作栏：计数、删除进度、全选已加载、退出与错误提示。
// 组件只负责呈现与回调，选择状态和删除流程由 LibraryPage 持有。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 底部批量操作栏；[deleting] 时显示「删除中 x/y」进度并把退出替换为停止剩余批次。
class LibrarySelectionBar extends StatelessWidget {
  const LibrarySelectionBar({
    super.key,
    required this.selectedCount,
    required this.deleting,
    required this.deleteTotal,
    required this.deleteDone,
    required this.onSelectAll,
    required this.onDelete,
    required this.onCancelOrStop,
    this.error,
  });

  final int selectedCount;

  /// 是否正在执行批量删除；为 true 时隐藏计数改用进度，按钮区只剩停止。
  final bool deleting;

  /// 本批次确认删除的总数；仅在 [deleting] 时使用。
  final int deleteTotal;

  /// 本批次已完成请求的条数（含失败）；仅在 [deleting] 时使用。
  final int deleteDone;

  /// 全选当前已加载项。
  final VoidCallback onSelectAll;

  /// 触发删除已选图片。
  final VoidCallback onDelete;

  /// 普通态退出选择；删除中语义为「停止剩余批次」（当前请求完成即止）。
  final VoidCallback onCancelOrStop;

  /// 最近一次批次的失败/提示信息；删除中不展示。
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LumaLayout.pagePaddingH,
          vertical: LumaSpacing.xs,
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: LumaSpacing.sm,
          runSpacing: LumaSpacing.xs,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (deleting) ...[
                  const SizedBox(
                    width: LumaIconSize.status,
                    height: LumaIconSize.status,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: LumaSpacing.xs),
                ],
                Text(
                  deleting
                      ? '删除中 $deleteDone/$deleteTotal'
                      : '已选 $selectedCount 项',
                  style: textTheme.titleSmall,
                ),
              ],
            ),
            Wrap(
              spacing: LumaSpacing.xs,
              runSpacing: LumaSpacing.xs,
              children: [
                if (!deleting) ...[
                  TextButton.icon(
                    onPressed: onSelectAll,
                    icon: const Icon(Icons.select_all_rounded),
                    label: const Text('全选已加载'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    ),
                    onPressed: selectedCount == 0 ? null : onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text('删除($selectedCount)'),
                  ),
                ],
                TextButton.icon(
                  onPressed: onCancelOrStop,
                  icon: Icon(
                    deleting ? Icons.stop_rounded : Icons.close_rounded,
                  ),
                  label: Text(deleting ? '停止剩余' : '退出选择'),
                ),
              ],
            ),
            if (!deleting && error != null)
              Text(
                error!,
                style: textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
          ],
        ),
      ),
    );
  }
}
