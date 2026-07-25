// 作品详情页的影院色板与局部 Theme 只服务于 catalog 详情组件。
// 页面进入时应用它，离开页面后不影响全局主题。
import 'package:flutter/material.dart';

abstract final class CatalogDetailPalette {
  static const background = Color(0xFF171815);
  static const surface = Color(0xFF20211D);
  static const text = Color(0xFFF2E7D3);
  static const muted = Color(0xFFC9BFAE);
  static const outline = Color(0xFF6C614D);
  static const accent = Color(0xFFF0A528);
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
      surfaceContainerHigh: const Color(0xFF30312B),
      outline: CatalogDetailPalette.outline,
      outlineVariant: const Color(0xFF403D34),
      primary: CatalogDetailPalette.accent,
      onPrimary: CatalogDetailPalette.background,
    ),
    textTheme: theme.textTheme.apply(
      bodyColor: CatalogDetailPalette.text,
      displayColor: CatalogDetailPalette.text,
    ),
  );
}
