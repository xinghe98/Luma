// TV 主题以远距离阅读层级和明确焦点区分标题、内容与操作。
// 仅由 television 分支应用，沿用普通主题的配色与用户主题选择。
import 'package:flutter/material.dart';

import 'tokens.dart';

/// applyTvTheme 返回适合电视观看的 [base] 副本；仅 television 分支调用。
///
/// 不缩放 MediaQuery、不改变 TextScaler：系统大字体设置继续生效，
/// 各输入框与卡片文字区域需按实际文字高度布局。
ThemeData applyTvTheme(ThemeData base) {
  final text = base.textTheme;
  TextStyle? size(TextStyle? style, double fontSize) =>
      style?.copyWith(fontSize: fontSize);

  final tvText = text.copyWith(
    headlineLarge: size(text.headlineLarge, 36),
    headlineMedium: size(text.headlineMedium, 30),
    headlineSmall: size(text.headlineSmall, 24),
    titleLarge: size(text.titleLarge, 24),
    titleMedium: size(text.titleMedium, 22),
    titleSmall: size(text.titleSmall, 18),
    bodyLarge: size(text.bodyLarge, 20),
    bodyMedium: size(text.bodyMedium, 18),
    bodySmall: size(text.bodySmall, 16),
    labelLarge: size(text.labelLarge, 18),
    labelMedium: size(text.labelMedium, 16),
    labelSmall: size(text.labelSmall, 14),
  );

  // 组件主题已保存普通端文字样式，只改 textTheme 不会传到实际控件。
  TextStyle? componentText(TextStyle? original, TextStyle? role) =>
      original?.copyWith(fontSize: role?.fontSize) ?? role;

  ButtonStyle buttonStyle(ButtonStyle? original) =>
      (original ?? const ButtonStyle()).copyWith(
        minimumSize: const WidgetStatePropertyAll(
          Size(0, LumaTvLayout.controlMinHeight),
        ),
        textStyle: WidgetStateProperty.resolveWith(
          (states) => componentText(
            original?.textStyle?.resolve(states),
            tvText.labelLarge,
          ),
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(
              color: base.colorScheme.onSurface,
              width: LumaTvLayout.focusStroke,
            );
          }
          return original?.side?.resolve(states);
        }),
      );

  return base.copyWith(
    textTheme: tvText,
    appBarTheme: base.appBarTheme.copyWith(
      toolbarHeight: 72,
      titleTextStyle: tvText.headlineSmall,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: buttonStyle(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttonStyle(base.textButtonTheme.style),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: componentText(
        base.listTileTheme.titleTextStyle,
        tvText.titleMedium,
      ),
      subtitleTextStyle: componentText(
        base.listTileTheme.subtitleTextStyle,
        tvText.bodySmall,
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      titleTextStyle: componentText(
        base.dialogTheme.titleTextStyle,
        tvText.titleLarge,
      ),
      contentTextStyle: componentText(
        base.dialogTheme.contentTextStyle,
        tvText.bodyMedium,
      ),
    ),
  );
}
