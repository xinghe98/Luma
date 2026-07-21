import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/layout/section_header.dart';

class RecentSearches extends StatelessWidget {
  const RecentSearches({
    super.key,
    required this.terms,
    required this.onSelect,
    required this.onClear,
  });

  final List<String> terms;
  final ValueChanged<String> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: LumaSpacing.lg),
        SectionHeader(
          title: '最近搜索',
          action: TextButton(onPressed: onClear, child: const Text('清除')),
        ),
        const SizedBox(height: LumaSpacing.xs),
        Wrap(
          spacing: LumaSpacing.xs,
          children: terms
              .map(
                (term) => ActionChip(
                  label: Text(term),
                  avatar: const Icon(Icons.history_rounded, size: 16),
                  onPressed: () => onSelect(term),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
