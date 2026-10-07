// TV 主题放大阅读层级，并用明度差标出焦点，而不是在主题色上叠一条近色描边。
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

  bool focused(Set<WidgetState> states) =>
      states.contains(WidgetState.focused) &&
      !states.contains(WidgetState.disabled);

  // 深色主题的主色本身就很亮，白描边几乎看不见。静止时收成容器色，
  // 获焦再亮回主色，文字跟着翻色。未处理的状态返回 null，继续用组件默认色。
  ButtonStyle buttonStyle(ButtonStyle? original, {required bool filled}) {
    final scheme = base.colorScheme;
    return (original ?? const ButtonStyle()).copyWith(
      minimumSize: const WidgetStatePropertyAll(
        Size(0, LumaTvLayout.controlMinHeight),
      ),
      textStyle: WidgetStateProperty.resolveWith(
        (states) => componentText(
          original?.textStyle?.resolve(states),
          tvText.labelLarge,
        ),
      ),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (focused(states)) return Colors.transparent;
        return null;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return null;
        if (!filled && !focused(states)) return null;
        return focused(states) ? scheme.primary : scheme.primaryContainer;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return null;
        if (focused(states)) return scheme.onPrimary;
        return filled ? scheme.onPrimaryContainer : null;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (!focused(states)) return original?.side?.resolve(states);
        final ring = scheme.primary.computeLuminance() > 0.45
            ? scheme.surface
            : scheme.onSurface;
        return BorderSide(color: ring, width: LumaTvLayout.focusStroke);
      }),
    );
  }

  // 图标按钮没有稳定的主题色底，获焦直接翻成反色底板。
  ButtonStyle iconStyle(ButtonStyle? original) {
    final scheme = base.colorScheme;
    return (original ?? const ButtonStyle()).copyWith(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (focused(states)) return Colors.transparent;
        return null;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (!focused(states)) return null;
        return scheme.inverseSurface;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (!focused(states)) return null;
        return scheme.onInverseSurface;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (!focused(states)) return original?.side?.resolve(states);
        return BorderSide(
          color: scheme.onSurface,
          width: LumaTvLayout.focusStroke,
        );
      }),
    );
  }

  return base.copyWith(
    textTheme: tvText,
    appBarTheme: base.appBarTheme.copyWith(
      toolbarHeight: 72,
      titleTextStyle: tvText.headlineSmall,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: buttonStyle(base.filledButtonTheme.style, filled: true),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle(base.outlinedButtonTheme.style, filled: false),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttonStyle(base.textButtonTheme.style, filled: false),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: iconStyle(base.iconButtonTheme.style),
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
