// 媒体库已生效筛选的横向展示条：状态与收藏条件以 InputChip 呈现，可单项移除。
// 仅展示与回传，筛选状态仍由 LibraryController 持有。
import 'package:flutter/material.dart';

import '../../../data/models/media_types.dart';
import '../../../core/theme.dart';
import '../library_controller.dart';

/// 当前筛选条件的可视化条；无附加筛选时不渲染内容。
class ActiveFilterBar extends StatelessWidget {
  /// 构建筛选条；[controller] 的 status/favoritesOnly 决定各 chip 是否出现。
  const ActiveFilterBar({super.key, required this.controller});

  final LibraryController controller;

  /// 观看状态筛选的展示文案；与筛选抽屉中的选项一致。
  static String statusLabel(WatchStatus status) => switch (status) {
    WatchStatus.unwatched => '未观看',
    WatchStatus.watching => '观看中',
    WatchStatus.watched => '已观看',
  };

  @override
  Widget build(BuildContext context) {
    if (!controller.hasExtraFilters) return const SizedBox.shrink();
    final status = controller.status;
    return Wrap(
      spacing: LumaSpacing.xs,
      runSpacing: LumaSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (status != null)
          InputChip(
            label: Text('状态：${statusLabel(status)}'),
            onDeleted: () => controller.applyFilters(
              LibraryFilters(
                status: null,
                favoritesOnly: controller.favoritesOnly,
              ),
            ),
          ),
        if (controller.favoritesOnly)
          InputChip(
            label: const Text('仅收藏'),
            onDeleted: () => controller.applyFilters(
              LibraryFilters(
                status: controller.status,
                favoritesOnly: false,
              ),
            ),
          ),
        TextButton(
          onPressed: controller.clearFilters,
          child: const Text('清除全部'),
        ),
      ],
    );
  }
}
