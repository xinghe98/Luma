// 作品详情页的影院色板与局部 Theme 只服务于 catalog 详情组件。
// 页面进入时应用它，离开页面后不影响全局主题。
import 'package:flutter/material.dart';

abstract final class CatalogDetailPalette {
  static const background = Color(0xFF101722);
  static const surface = Color(0xFF182235);
  static const surfaceHigh = Color(0xFF253149);
  static const text = Color(0xFFF1F5FC);
  static const muted = Color(0xFFBBC6D8);
  static const outline = Color(0xFF62738F);
  static const outlineVariant = Color(0xFF35435B);
  static const accent = Color(0xFF8FB6FF);
  static const onAccent = Color(0xFF10203A);
}

/// 为详情内容建立局部暗色主题，不修改应用其他页面的配色。
ThemeData catalogDetailTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      surface: CatalogDetailPalette.background,
      onSurface: CatalogDetailPalette.text,
      onSurfaceVariant: CatalogDetailPalette.muted,
      surfaceContainerLow: CatalogDetailPalette.surface,
      surfaceContainerHigh: CatalogDetailPalette.surfaceHigh,
      outline: CatalogDetailPalette.outline,
      outlineVariant: CatalogDetailPalette.outlineVariant,
      primary: CatalogDetailPalette.accent,
      onPrimary: CatalogDetailPalette.onAccent,
    ),
    textTheme: theme.textTheme.apply(
      bodyColor: CatalogDetailPalette.text,
      displayColor: CatalogDetailPalette.text,
    ),
  );
}
