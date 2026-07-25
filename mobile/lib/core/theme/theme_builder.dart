import 'package:flutter/material.dart';

import 'theme_components.dart';
import 'theme_extension.dart';
import 'tokens.dart';

final class LumaThemeBuilder {
  const LumaThemeBuilder._();

  static ThemeData build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? LumaColors.darkPrimary : LumaColors.lightPrimary,
      onPrimary: isDark ? LumaColors.deepBlue : LumaColors.paper,
      primaryContainer: isDark
          ? LumaColors.darkPrimaryContainer
          : LumaColors.lightPrimaryContainer,
      onPrimaryContainer: isDark ? LumaColors.onInk : LumaColors.ink,
      secondary: isDark ? LumaColors.gold : LumaColors.lightSecondary,
      onSecondary: isDark ? LumaColors.deepBlue : LumaColors.paper,
      secondaryContainer: isDark
          ? LumaColors.darkSecondaryContainer
          : LumaColors.lightSecondaryContainer,
      onSecondaryContainer: isDark ? LumaColors.onInk : LumaColors.ink,
      tertiary: isDark ? LumaColors.darkTertiary : LumaColors.lightTertiary,
      onTertiary: isDark ? LumaColors.deepBlue : LumaColors.paper,
      tertiaryContainer: isDark
          ? LumaColors.darkTertiaryContainer
          : LumaColors.lightTertiaryContainer,
      onTertiaryContainer: isDark ? LumaColors.onInk : LumaColors.ink,
      error: LumaColors.error,
      onError: LumaColors.onError,
      errorContainer: isDark
          ? LumaColors.darkErrorContainer
          : LumaColors.lightErrorContainer,
      onErrorContainer: isDark
          ? LumaColors.darkOnErrorContainer
          : LumaColors.lightOnErrorContainer,
      surface: isDark ? LumaColors.deepBlue : LumaColors.paper,
      onSurface: isDark ? LumaColors.onInk : LumaColors.ink,
      surfaceDim: isDark ? LumaColors.ink : LumaColors.lightSurfaceDim,
      surfaceBright: isDark ? LumaColors.darkSurfaceBright : LumaColors.paper,
      surfaceContainerLowest: isDark ? LumaColors.ink : LumaColors.paper,
      surfaceContainerLow: isDark ? LumaColors.deepBlue : LumaColors.paper,
      surfaceContainer: isDark
          ? LumaColors.surface
          : LumaColors.lightSurfaceContainer,
      surfaceContainerHigh: isDark
          ? LumaColors.elevated
          : LumaColors.lightSurfaceContainerHigh,
      surfaceContainerHighest: isDark
          ? LumaColors.elevated
          : LumaColors.lightSurfaceContainerHigh,
      outline: isDark ? LumaColors.darkOutline : LumaColors.lightOutline,
      outlineVariant: isDark
          ? LumaColors.darkOutlineVariant
          : LumaColors.lightOutlineVariant,
      shadow: LumaColors.ink,
      scrim: LumaColors.ink,
      inverseSurface: isDark ? LumaColors.paper : LumaColors.ink,
      onInverseSurface: isDark ? LumaColors.ink : LumaColors.onInk,
      inversePrimary: isDark ? LumaColors.lightPrimary : LumaColors.darkPrimary,
      surfaceTint: isDark ? LumaColors.darkPrimary : LumaColors.lightPrimary,
    );

    final scaffold = isDark ? LumaColors.deepBlue : LumaColors.paper;
    final extras = isDark ? LumaExtras.dark : LumaExtras.light;
    final radiusMd = BorderRadius.circular(LumaRadii.medium);
    final buttonShape = RoundedRectangleBorder(borderRadius: radiusMd);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: LumaTypography.fontFamily,
      fontFamilyFallback: LumaTypography.fontFamilyFallback,
      extensions: [extras],
    );

    final textTheme = LumaTypography.buildTextTheme(base.textTheme);

    return applyLumaComponentThemes(
      base: base,
      scheme: scheme,
      scaffold: scaffold,
      textTheme: textTheme,
      radiusMd: radiusMd,
      buttonShape: buttonShape,
    );
  }
}
