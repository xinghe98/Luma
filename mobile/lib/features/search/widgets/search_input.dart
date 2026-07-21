import 'package:flutter/material.dart';

class SearchInput extends StatelessWidget {
  const SearchInput({
    super.key,
    required this.textController,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController textController;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      controller: textController,
      hintText: '搜索标题、标签或格式',
      leading: const Icon(Icons.search_rounded),
      trailing: [
        if (textController.text.isNotEmpty)
          IconButton(
            tooltip: '清除',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded),
          ),
      ],
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}
