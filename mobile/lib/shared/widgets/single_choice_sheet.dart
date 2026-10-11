import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../interaction/tv_key_bindings.dart';

@immutable
class BottomSheetChoice<T> {
  const BottomSheetChoice({
    required this.value,
    required this.label,
    required this.icon,
    this.description,
  });

  final T value;
  final String label;
  final IconData icon;
  final String? description;
}

/// 在宽屏使用居中对话框、窄屏使用底部抽屉，返回用户选中的值。
/// TV 一律使用居中对话框并默认聚焦选中项，内容与返回值保持不变。
Future<T?> showSingleChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required String supportingText,
  required T? selectedValue,
  required List<BottomSheetChoice<T>> choices,
}) {
  final isTelevision =
      AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false;
  final content = _SingleChoiceSheet<T>(
    title: title,
    supportingText: supportingText,
    selectedValue: selectedValue,
    choices: choices,
    autofocusSelected: isTelevision,
  );
  if (isTelevision ||
      MediaQuery.sizeOf(context).width >= LumaLayout.navigationRailBreakpoint) {
    return showDialog<T>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          // 弹窗是独立路由，需自行消费确认键的长按重复。
          child: isTelevision ? TvKeyBindings(child: content) : content,
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => content,
  );
}

class _SingleChoiceSheet<T> extends StatefulWidget {
  const _SingleChoiceSheet({
    required this.title,
    required this.supportingText,
    required this.selectedValue,
    required this.choices,
    this.autofocusSelected = false,
  });

  final String title;
  final String supportingText;
  final T? selectedValue;
  final List<BottomSheetChoice<T>> choices;

  /// TV 弹层打开时默认聚焦当前选中项，遥控器立即可操作。
  final bool autofocusSelected;

  @override
  State<_SingleChoiceSheet<T>> createState() => _SingleChoiceSheetState<T>();
}

class _SingleChoiceSheetState<T> extends State<_SingleChoiceSheet<T>> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.autofocusSelected) {
      // 自动聚焦不会触发方向遍历的滚动；首帧布局后显示选中项。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final selectedContext = _selectedKey.currentContext;
        if (selectedContext != null) {
          Scrollable.ensureVisible(
            selectedContext,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: SingleChildScrollView(
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                // 所有调用方共用同一关闭动作；触控 48dp 与 Back/Escape 等价。
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: LumaSpacing.xs),
            Text(
              widget.supportingText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: LumaSpacing.md),
            for (final choice in widget.choices)
              _SingleChoiceTile<T>(
                key:
                    widget.autofocusSelected &&
                        choice.value == widget.selectedValue
                    ? _selectedKey
                    : null,
                choice: choice,
                selected: choice.value == widget.selectedValue,
                autofocus:
                    widget.autofocusSelected &&
                    choice.value == widget.selectedValue,
              ),
          ],
        ),
      ),
    );
  }
}

class _SingleChoiceTile<T> extends StatelessWidget {
  const _SingleChoiceTile({
    super.key,
    required this.choice,
    required this.selected,
    this.autofocus = false,
  });

  final BottomSheetChoice<T> choice;
  final bool selected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: ListTile(
        autofocus: autofocus,
        contentPadding: EdgeInsets.zero,
        selected: selected,
        selectedColor: scheme.primary,
        leading: Icon(choice.icon),
        title: Text(choice.label),
        subtitle: choice.description == null ? null : Text(choice.description!),
        trailing: SizedBox(
          width: LumaIconSize.action,
          child: selected
              ? Icon(Icons.check_rounded, color: scheme.primary)
              : null,
        ),
        onTap: () => Navigator.of(context).pop(choice.value),
      ),
    );
  }
}
