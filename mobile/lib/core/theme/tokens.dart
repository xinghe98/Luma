import 'package:flutter/material.dart';

abstract final class LumaColors {
  static const ink = Color(0xFF2C3433);
  static const deepBlue = Color(0xFF2E322F);
  static const surface = Color(0xFF3A3D38);
  static const elevated = Color(0xFF484A44);
  static const gold = Color(0xFFB48A4B);
  static const paper = Color(0xFFEEE6DA);
  static const success = Color(0xFF8EAD92);
  static const warning = Color(0xFFC1A064);
  static const lightSuccess = Color(0xFF356746);
  static const lightWarning = Color(0xFF765617);
  static const lightPrimary = Color(0xFF535853);
  static const darkPrimary = Color(0xFFC5C6BD);
  static const lightSecondary = Color(0xFF756035);
  static const lightSurfaceContainer = Color(0xFFE1D9CD);
  static const lightSurfaceContainerHigh = Color(0xFFD4CCC0);
  static const onInk = Color(0xFFF7F0E6);
  static const onInkMuted = Color(0xB3F7F0E6);
  static const lightPrimaryContainer = Color(0xFFDAD8CD);
  static const lightSecondaryContainer = Color(0xFFE7D8BE);
  static const lightTertiary = Color(0xFF705E55);
  static const lightTertiaryContainer = Color(0xFFE5D6CC);
  static const lightOutline = Color(0xFF79776E);
  static const lightOutlineVariant = Color(0xFFC8C1B7);
  static const darkPrimaryContainer = Color(0xFF52554F);
  static const darkSecondaryContainer = Color(0xFF5D502F);
  static const darkTertiary = Color(0xFFD5BFB3);
  static const darkTertiaryContainer = Color(0xFF594940);
  static const darkOutline = Color(0xFF97938A);
  static const darkOutlineVariant = Color(0xFF4B4A44);
  static const lightSurfaceDim = Color(0xFFD9D1C5);
  static const darkSurfaceBright = Color(0xFF464842);
  static const error = Color(0xFFB3261E);
  static const onError = Color(0xFFFFF8F6);
  static const lightErrorContainer = Color(0xFFFFDAD5);
  static const lightOnErrorContainer = Color(0xFF410002);
  static const darkErrorContainer = Color(0xFF8C1D18);
  static const darkOnErrorContainer = Color(0xFFFFDAD5);
  static const lightBadgeScrim = Color(0x9A2C3433);
  static const darkBadgeScrim = Color(0xB32C3433);
}

abstract final class LumaArtworkColors {
  static const palettes = <List<Color>>[
    [Color(0xFF5A5C56), Color(0xFF2C3433), LumaColors.gold],
    [Color(0xFF665F58), Color(0xFF353632), Color(0xFFA88B72)],
    [Color(0xFF4A504B), Color(0xFF282C29), Color(0xFFA5A093)],
    [Color(0xFF6A5346), Color(0xFF332F2E), Color(0xFFC0A06B)],
    [Color(0xFF555851), Color(0xFF2B2E2B), Color(0xFFA99A81)],
  ];
}

abstract final class LumaTypography {
  static const fontFamily = 'MiSans';
  static const fontFamilyFallback = <String>['sans-serif'];

  static TextTheme buildTextTheme(TextTheme base) {
    final themed = base.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
    return themed.copyWith(
      displayLarge: themed.displayLarge?.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
      displayMedium: themed.displayMedium?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
      displaySmall: themed.displaySmall?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
      headlineLarge: themed.headlineLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
      headlineMedium: themed.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
      headlineSmall: themed.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
      titleLarge: themed.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.35,
        letterSpacing: 0,
      ),
      titleSmall: themed.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: 0,
      ),
      bodyLarge: themed.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodyMedium: themed.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        letterSpacing: 0,
      ),
      bodySmall: themed.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.5,
        letterSpacing: 0,
      ),
      labelLarge: themed.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0,
      ),
      labelMedium: themed.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 0,
      ),
      labelSmall: themed.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 0,
      ),
    );
  }
}

abstract final class LumaLayout {
  static const contentMaxWidth = 1280.0;
  static const detailMaxWidth = 1160.0;
  static const formMaxWidth = 520.0;
  static const navigationRailBreakpoint = 840.0;
  static const extendedRailBreakpoint = 1100.0;
  static const detailTwoColumnBreakpoint = 760.0;
  static const horizontalCardWidth = 232.0;
  static const horizontalCardHeight = 202.0;
  static const pagePaddingH = 20.0;
  static const pagePaddingTop = 12.0;
  static const pagePaddingBottom = 40.0;
  static const buttonHeight = 52.0;
  static const navigationBarHeight = 68.0;
  static const minTapTarget = 48.0;

  static const scrollCacheExtent = 320.0;

  static EdgeInsets pagePadding({
    double top = pagePaddingTop,
    double bottom = pagePaddingBottom,
  }) => EdgeInsets.fromLTRB(pagePaddingH, top, pagePaddingH, bottom);

  static int gridColumns(double width) => width >= 1200
      ? 5
      : width >= 900
      ? 4
      : width >= 600
      ? 3
      : 2;

  static double mediaCardAspectRatio(double gridWidth) {
    final count = gridColumns(gridWidth);
    final cardWidth = (gridWidth - LumaSpacing.md * (count - 1)) / count;
    return cardWidth / (cardWidth / 1.6 + 66);
  }
}

abstract final class LumaSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class LumaRadii {
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 18.0;
  static const badge = 8.0;
}

abstract final class LumaMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);
  static const Curve standard = Curves.easeOutCubic;

  static Duration forContext(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
