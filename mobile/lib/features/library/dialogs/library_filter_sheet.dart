import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_types.dart';
import '../../../shared/layout/adaptive_action_width.dart';
import '../library_controller.dart';

/// 在桌面端使用对话框、触控布局使用底部抽屉，并返回应用后的筛选条件。
Future<LibraryFilters?> showLibraryFilterSheet(
  BuildContext context,
  LibraryFilters initial, {
  required bool showWatchStatus,
}) {
  var status = showWatchStatus ? initial.status : null;
  var favoritesOnly = initial.favoritesOnly;
  Widget buildContent(BuildContext dialogContext, StateSetter setSheetState) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(
          LumaLayout.pagePaddingH,
          LumaSpacing.lg,
          LumaLayout.pagePaddingH,
          LumaSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('筛选媒体', style: Theme.of(dialogContext).textTheme.titleLarge),
            const SizedBox(height: LumaSpacing.lg),
            if (showWatchStatus) ...[
              Text('观看状态', style: Theme.of(dialogContext).textTheme.labelLarge),
              const SizedBox(height: LumaSpacing.xs),
              Wrap(
                spacing: LumaSpacing.xs,
                children: [
                  _StatusChip(
                    label: '不限',
                    value: null,
                    selected: status,
                    onSelect: (v) => setSheetState(() => status = v),
                  ),
                  _StatusChip(
                    label: '未观看',
                    value: WatchStatus.unwatched,
                    selected: status,
                    onSelect: (v) => setSheetState(() => status = v),
                  ),
                  _StatusChip(
                    label: '观看中',
                    value: WatchStatus.watching,
                    selected: status,
                    onSelect: (v) => setSheetState(() => status = v),
                  ),
                  _StatusChip(
                    label: '已观看',
                    value: WatchStatus.watched,
                    selected: status,
                    onSelect: (v) => setSheetState(() => status = v),
                  ),
                ],
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅显示收藏'),
              value: favoritesOnly,
              onChanged: (value) => setSheetState(() => favoritesOnly = value),
            ),
            const SizedBox(height: LumaSpacing.sm),
            AdaptiveActionWidth(
              maxWidth: 240,
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  LibraryFilters(status: status, favoritesOnly: favoritesOnly),
                ),
                child: const Text('应用筛选'),
              ),
            ),
          ],
        ),
      );

  if (MediaQuery.sizeOf(context).width >= LumaLayout.navigationRailBreakpoint) {
    return showDialog<LibraryFilters>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: StatefulBuilder(
            builder: (context, setSheetState) =>
                buildContent(context, setSheetState),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<LibraryFilters>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: StatefulBuilder(
        builder: (context, setSheetState) =>
            buildContent(context, setSheetState),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final WatchStatus? value;
  final WatchStatus? selected;
  final ValueChanged<WatchStatus?> onSelect;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected == value,
    onSelected: (_) => onSelect(value),
  );
}
