import 'package:flutter/material.dart';

abstract final class LumaColors {
  static const ink = Color(0xFF182236);
  static const deepBlue = Color(0xFF111827);
  static const surface = Color(0xFF172033);
  static const elevated = Color(0xFF212C3E);
  static const accentBlue = Color(0xFF8FB6FF);
  static const paper = Color(0xFFF3F6FC);
  static const success = Color(0xFF87C9A0);
  static const warning = Color(0xFFE2B86B);
  static const lightSuccess = Color(0xFF2F7650);
  static const lightWarning = Color(0xFF805A14);
  static const lightPrimary = Color(0xFF426FC4);
  static const darkPrimary = Color(0xFFA9C7FF);
  static const lightSecondary = Color(0xFF536D9D);
  static const lightSurfaceContainer = Color(0xFFFBFCFF);
  static const lightSurfaceContainerHigh = Color(0xFFEAF0F9);
  static const onInk = Color(0xFFEEF3FB);
  static const onInkMuted = Color(0xBDB7C1D0);
  static const lightPrimaryContainer = Color(0xFFDCE8FB);
  static const lightSecondaryContainer = Color(0xFFE4EBF7);
  static const lightTertiary = Color(0xFF5F6684);
  static const lightTertiaryContainer = Color(0xFFE8E9F4);
  static const lightOutline = Color(0xFF647084);
  static const lightOutlineVariant = Color(0xFFD5DEEB);
  static const darkPrimaryContainer = Color(0xFF294771);
  static const darkSecondaryContainer = Color(0xFF293950);
  static const darkTertiary = Color(0xFFC2C7E5);
  static const darkTertiaryContainer = Color(0xFF373B58);
  static const darkOutline = Color(0xFF9BA8BC);
  static const darkOutlineVariant = Color(0xFF435169);
  static const lightSurfaceDim = Color(0xFFE6ECF5);
  static const darkSurfaceBright = Color(0xFF2B374B);
  static const lightBrandSurface = Color(0xFFE8F0FC);
  static const lightBrandSurfaceVariant = Color(0xFFF5F8FD);
  static const darkBrandSurface = Color(0xFF1B2940);
  static const darkBrandSurfaceVariant = Color(0xFF243650);
  static const error = Color(0xFFB3261E);
  static const onError = Color(0xFFFFF8F6);
  static const lightErrorContainer = Color(0xFFFFDAD5);
  static const lightOnErrorContainer = Color(0xFF410002);
  static const darkErrorContainer = Color(0xFF8C1D18);
  static const darkOnErrorContainer = Color(0xFFFFDAD5);
  static const lightBadgeScrim = Color(0xA6182236);
  static const darkBadgeScrim = Color(0xC4111827);
}

abstract final class LumaArtworkColors {
  static const palettes = <List<Color>>[
    [Color(0xFF7190C6), Color(0xFF33435F), Color(0xFFA9C7FF)],
    [Color(0xFF7D88AC), Color(0xFF394159), Color(0xFFB7C8E8)],
    [Color(0xFF71879A), Color(0xFF34444F), Color(0xFFA8C4D9)],
    [Color(0xFF857D9E), Color(0xFF433D54), Color(0xFFC1B9DD)],
    [Color(0xFF6F829C), Color(0xFF354052), Color(0xFFAABCD5)],
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
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0,
      ),
      displayMedium: themed.displayMedium?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0,
      ),
      displaySmall: themed.displaySmall?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0,
      ),
      headlineLarge: themed.headlineLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0,
      ),
      headlineMedium: themed.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0,
      ),
      headlineSmall: themed.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
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
  static const pagePaddingTabletH = 28.0;
  static const pagePaddingWideH = 32.0;
  static const pagePaddingTop = 12.0;
  static const pagePaddingBottom = 40.0;
  static const buttonHeight = 52.0;
  static const navigationBarHeight = 68.0;
  static const minTapTarget = 48.0;
  static const inputHeight = 52.0;
  static const compactControlHeight = 48.0;
  static const chipHeight = 40.0;

  static const scrollCacheExtent = 320.0;

  static EdgeInsets pagePadding({
    double top = pagePaddingTop,
    double bottom = pagePaddingBottom,
  }) => EdgeInsets.fromLTRB(pagePaddingH, top, pagePaddingH, bottom);

  /// 根据可用宽度返回统一页面边距，宽屏只增加呼吸感而不改变内容结构。
  static double pageHorizontalPadding(double width) => width >= 840
      ? pagePaddingWideH
      : width >= 600
      ? pagePaddingTabletH
      : pagePaddingH;

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
  static const small = 12.0;
  static const medium = 16.0;
  static const large = 22.0;
  static const extraLarge = 30.0;
  static const badge = 999.0;
}

abstract final class LumaIconSize {
  static const status = 18.0;
  static const inline = 22.0;
  static const action = 24.0;
  static const prominent = 28.0;
  static const emptyState = 40.0;
}

abstract final class LumaStroke {
  static const hairline = 1.0;
  static const focused = 1.5;
}

abstract final class LumaMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration navigation = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 250);
  static const Curve standard = Curves.easeOutCubic;

  static Duration forContext(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
