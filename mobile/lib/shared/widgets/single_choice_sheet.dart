import 'package:flutter/material.dart';

import '../../core/theme.dart';

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

Future<T?> showSingleChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required String supportingText,
  required T? selectedValue,
  required List<BottomSheetChoice<T>> choices,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) => _SingleChoiceSheet<T>(
    title: title,
    supportingText: supportingText,
    selectedValue: selectedValue,
    choices: choices,
  ),
);

class _SingleChoiceSheet<T> extends StatelessWidget {
  const _SingleChoiceSheet({
    required this.title,
    required this.supportingText,
    required this.selectedValue,
    required this.choices,
  });

  final String title;
  final String supportingText;
  final T? selectedValue;
  final List<BottomSheetChoice<T>> choices;

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
          LumaSpacing.xxs,
          LumaLayout.pagePaddingH,
          LumaSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: LumaSpacing.xs),
            Text(
              supportingText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: LumaSpacing.md),
            for (final choice in choices)
              _SingleChoiceTile<T>(
                choice: choice,
                selected: choice.value == selectedValue,
              ),
          ],
        ),
      ),
    );
  }
}

class _SingleChoiceTile<T> extends StatelessWidget {
  const _SingleChoiceTile({required this.choice, required this.selected});

  final BottomSheetChoice<T> choice;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        selected: selected,
        selectedColor: scheme.primary,
        leading: Icon(choice.icon),
        title: Text(choice.label),
        subtitle: choice.description == null ? null : Text(choice.description!),
        trailing: SizedBox(
          width: 24,
          child: selected
              ? Icon(Icons.check_rounded, color: scheme.primary)
              : null,
        ),
        onTap: () => Navigator.of(context).pop(choice.value),
      ),
    );
  }
}
