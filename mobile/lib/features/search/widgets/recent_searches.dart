import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/layout/section_header.dart';

class RecentSearches extends StatelessWidget {
  const RecentSearches({
    super.key,
    required this.terms,
    required this.onSelect,
    required this.onClear,
    this.television = false,
  });

  final List<String> terms;
  final ValueChanged<String> onSelect;
  final VoidCallback onClear;

  /// TV 按需展开历史菜单，避免记录占据结果墙的垂直空间。
  final bool television;

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) return const SizedBox.shrink();
    if (television) {
      return PopupMenuButton<int>(
        tooltip: '最近搜索',
        onSelected: (index) {
          if (index == terms.length) {
            onClear();
          } else {
            onSelect(terms[index]);
          }
        },
        itemBuilder: (_) => [
          for (var index = 0; index < terms.length; index++)
            PopupMenuItem(value: index, child: Text(terms[index])),
          const PopupMenuDivider(),
          PopupMenuItem(value: terms.length, child: const Text('清除搜索记录')),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded),
              SizedBox(width: 10),
              Text('最近搜索'),
              Icon(Icons.arrow_drop_down_rounded),
            ],
          ),
        ),
      );
    }
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
