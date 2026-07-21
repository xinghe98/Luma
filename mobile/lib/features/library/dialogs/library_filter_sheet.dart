import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_types.dart';
import '../library_controller.dart';

Future<LibraryFilters?> showLibraryFilterSheet(
  BuildContext context,
  LibraryFilters initial, {
  required bool showWatchStatus,
}) {
  var status = showWatchStatus ? initial.status : null;
  var favoritesOnly = initial.favoritesOnly;
  return showModalBottomSheet<LibraryFilters>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('筛选媒体', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: LumaSpacing.lg),
              if (showWatchStatus) ...[
                const Text('观看状态'),
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
                onChanged: (value) =>
                    setSheetState(() => favoritesOnly = value),
              ),
              const SizedBox(height: LumaSpacing.sm),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  LibraryFilters(status: status, favoritesOnly: favoritesOnly),
                ),
                child: const Text('应用筛选'),
              ),
            ],
          ),
        ),
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
