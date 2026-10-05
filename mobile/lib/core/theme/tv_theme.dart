// TV 主题在既有 Luma 主题上放大文字与控件高度，供十英尺观看距离阅读。
// 只调整文字档位与按钮尺寸；配色、字体、圆角和动效完全沿用普通主题。
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
    headlineLarge: size(text.headlineLarge, 28),
    headlineMedium: size(text.headlineMedium, 28),
    headlineSmall: size(text.headlineSmall, 24),
    titleLarge: size(text.titleLarge, 24),
    titleMedium: size(text.titleMedium, 20),
    titleSmall: size(text.titleSmall, 20),
    bodyLarge: size(text.bodyLarge, 20),
    bodyMedium: size(text.bodyMedium, 18),
    bodySmall: size(text.bodySmall, 18),
    labelLarge: size(text.labelLarge, 20),
    labelMedium: size(text.labelMedium, 18),
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
      );

  return base.copyWith(
    textTheme: tvText,
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
