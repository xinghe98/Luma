import 'package:flutter/material.dart';

abstract final class LumaColors {
  static const ink = Color(0xFF101820);
  static const deepBlue = Color(0xFF131D27);
  static const surface = Color(0xFF1B2732);
  static const elevated = Color(0xFF24323E);
  static const mist = Color(0xFF9DBFC0);
  static const gold = Color(0xFFD0AA69);
  static const paper = Color(0xFFF3F5F4);
  static const success = Color(0xFF7BAF8A);
  static const warning = Color(0xFFD9A05B);
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

  /// 媒体网格列数断点，网格与骨架屏共用。
  static int gridColumns(double width) => width >= 1200
      ? 5
      : width >= 900
      ? 4
      : width >= 600
      ? 3
      : 2;

  /// 依据列宽动态计算卡片宽高比，避免宽屏下卡片被拉高。
  static double mediaCardAspectRatio(double gridWidth) {
    final count = gridColumns(gridWidth);
    final cardWidth = (gridWidth - LumaSpacing.md * (count - 1)) / count;
    // 文字区高度估算：8 间距 + 两行标题 + 2 间距 + 一行副标题。
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
}

abstract final class LumaTheme {
  static ThemeData? _dark;
  static ThemeData? _light;

  /// 主题实例只构建一次，避免每次重建都重复执行 ColorScheme.fromSeed。
  static ThemeData dark() => _dark ??= _build(Brightness.dark);

  static ThemeData light() => _light ??= _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: LumaColors.mist,
          brightness: brightness,
          surface: isDark ? LumaColors.deepBlue : LumaColors.paper,
        ).copyWith(
          primary: isDark ? const Color(0xFFA8CACA) : const Color(0xFF426D70),
          secondary: isDark ? LumaColors.gold : const Color(0xFF866629),
          surfaceContainer: isDark
              ? LumaColors.surface
              : const Color(0xFFE8ECEB),
          surfaceContainerHigh: isDark
              ? LumaColors.elevated
              : const Color(0xFFDDE3E2),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? LumaColors.deepBlue : LumaColors.paper,
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumaRadii.medium),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: base.scaffoldBackgroundColor,
        titleTextStyle: base.textTheme.titleLarge,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumaRadii.medium),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumaRadii.medium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumaRadii.medium),
          borderSide: BorderSide(color: scheme.outlineVariant.withAlpha(100)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumaRadii.medium),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer.withAlpha(150),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withAlpha(90),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
