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
      onPrimary: isDark ? LumaColors.darkOnPrimary : LumaColors.lightOnPrimary,
      primaryContainer: isDark
          ? LumaColors.darkPrimaryContainer
          : LumaColors.lightPrimaryContainer,
      onPrimaryContainer: isDark
          ? LumaColors.darkOnPrimaryContainer
          : LumaColors.lightOnPrimaryContainer,
      secondary: isDark ? LumaColors.darkSecondary : LumaColors.lightSecondary,
      onSecondary: isDark
          ? LumaColors.darkOnSecondary
          : LumaColors.lightOnSecondary,
      secondaryContainer: isDark
          ? LumaColors.darkSecondaryContainer
          : LumaColors.lightSecondaryContainer,
      onSecondaryContainer: isDark
          ? LumaColors.darkOnSecondaryContainer
          : LumaColors.lightOnSecondaryContainer,
      tertiary: isDark ? LumaColors.darkTertiary : LumaColors.lightTertiary,
      onTertiary: isDark
          ? LumaColors.darkOnTertiary
          : LumaColors.lightOnTertiary,
      tertiaryContainer: isDark
          ? LumaColors.darkTertiaryContainer
          : LumaColors.lightTertiaryContainer,
      onTertiaryContainer: isDark
          ? LumaColors.darkOnTertiaryContainer
          : LumaColors.lightOnTertiaryContainer,
      error: isDark ? LumaColors.darkError : LumaColors.lightError,
      onError: isDark ? LumaColors.darkOnError : LumaColors.lightOnError,
      errorContainer: isDark
          ? LumaColors.darkErrorContainer
          : LumaColors.lightErrorContainer,
      onErrorContainer: isDark
          ? LumaColors.darkOnErrorContainer
          : LumaColors.lightOnErrorContainer,
      surface: isDark ? LumaColors.darkSurface : LumaColors.lightSurface,
      onSurface: isDark ? LumaColors.darkOnSurface : LumaColors.lightOnSurface,
      onSurfaceVariant: isDark
          ? LumaColors.darkOnSurfaceVariant
          : LumaColors.lightOnSurfaceVariant,
      surfaceDim: isDark
          ? LumaColors.darkSurfaceDim
          : LumaColors.lightSurfaceDim,
      surfaceBright: isDark
          ? LumaColors.darkSurfaceBright
          : LumaColors.lightSurfaceBright,
      surfaceContainerLowest: isDark
          ? LumaColors.darkSurfaceContainerLowest
          : LumaColors.lightSurfaceContainerLowest,
      surfaceContainerLow: isDark
          ? LumaColors.darkSurfaceContainerLow
          : LumaColors.lightSurfaceContainerLow,
      surfaceContainer: isDark
          ? LumaColors.darkSurfaceContainer
          : LumaColors.lightSurfaceContainer,
      surfaceContainerHigh: isDark
          ? LumaColors.darkSurfaceContainerHigh
          : LumaColors.lightSurfaceContainerHigh,
      surfaceContainerHighest: isDark
          ? LumaColors.darkSurfaceContainerHighest
          : LumaColors.lightSurfaceContainerHighest,
      outline: isDark ? LumaColors.darkOutline : LumaColors.lightOutline,
      outlineVariant: isDark
          ? LumaColors.darkOutlineVariant
          : LumaColors.lightOutlineVariant,
      shadow: LumaColors.shadow,
      scrim: LumaColors.scrim,
      inverseSurface: isDark
          ? LumaColors.darkInverseSurface
          : LumaColors.lightInverseSurface,
      onInverseSurface: isDark
          ? LumaColors.darkOnInverseSurface
          : LumaColors.lightOnInverseSurface,
      inversePrimary: isDark
          ? LumaColors.darkInversePrimary
          : LumaColors.lightInversePrimary,
      surfaceTint: isDark ? LumaColors.darkPrimary : LumaColors.lightPrimary,
    );

    final scaffold = isDark ? LumaColors.darkSurface : LumaColors.lightSurface;
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
