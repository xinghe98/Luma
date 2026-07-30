import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 手机和桌面共用的搜索输入框，负责查询提交与清空入口。
class SearchInput extends StatelessWidget {
  const SearchInput({
    super.key,
    required this.textController,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController textController;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final FocusNode? focusNode;
  final bool autofocus;

  /// 构建固定高度且文字显式垂直居中的单行搜索框。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final searchTheme = SearchBarTheme.of(context);
    final states = <WidgetState>{};
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(LumaRadii.large),
      borderSide: BorderSide.none,
    );

    return SizedBox(
      key: const ValueKey('search-input-frame'),
      height: LumaLayout.inputHeight,
      child: TextField(
        controller: textController,
        focusNode: focusNode,
        autofocus: autofocus,
        textAlignVertical: TextAlignVertical.center,
        style:
            searchTheme.textStyle?.resolve(states) ?? theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: '搜索标题、标签或格式',
          hintStyle:
              searchTheme.hintStyle?.resolve(states) ??
              theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
          filled: true,
          fillColor:
              searchTheme.backgroundColor?.resolve(states) ??
              scheme.surfaceContainer,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: scheme.onSurface,
          ),
          prefixIconConstraints: const BoxConstraints.tightFor(
            width: LumaLayout.inputHeight + LumaSpacing.xxs,
            height: LumaLayout.inputHeight,
          ),
          suffixIcon: textController.text.isNotEmpty
              ? IconButton(
                  tooltip: '清除',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          suffixIconColor: scheme.onSurfaceVariant,
          suffixIconConstraints: const BoxConstraints.tightFor(
            width: LumaLayout.inputHeight + LumaSpacing.xxs,
            height: LumaLayout.inputHeight,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border,
          disabledBorder: border,
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}
