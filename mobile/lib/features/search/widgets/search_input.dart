import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 跨端搜索输入框；TV 闸门控制编辑焦点，页面提供独立提交与清空操作。
class SearchInput extends StatelessWidget {
  const SearchInput({
    super.key,
    required this.textController,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    this.focusNode,
    this.autofocus = false,
    this.television = false,
    this.remoteLayout = false,
  });

  final TextEditingController textController;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final FocusNode? focusNode;
  final bool autofocus;

  /// TV 外层闸门持浏览焦点时为 true，用主色描边提示可进入编辑。
  final bool television;

  /// 使用遥控输入尺寸和 IME 搜索键，清空入口由 TV 页面承接。
  final bool remoteLayout;

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
    final gateBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(LumaRadii.large),
      borderSide: BorderSide(color: scheme.primary, width: 2),
    );

    return SizedBox(
      key: const ValueKey('search-input-frame'),
      height: remoteLayout ? 64 : LumaLayout.inputHeight,
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
          prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurface),
          prefixIconConstraints: const BoxConstraints.tightFor(
            width: LumaLayout.inputHeight + LumaSpacing.xxs,
            height: LumaLayout.inputHeight,
          ),
          suffixIcon: !remoteLayout && textController.text.isNotEmpty
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
          enabledBorder: television ? gateBorder : border,
          focusedBorder: border,
          disabledBorder: border,
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: remoteLayout ? TextInputAction.search : null,
      ),
    );
  }
}
