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
  // Darker light-theme semantic colors preserve text/icon contrast on paper.
  static const lightSuccess = Color(0xFF2E6B3A);
  static const lightWarning = Color(0xFF805710);
  static const lightPrimary = Color(0xFF426D70);
  static const darkPrimary = Color(0xFFA8CACA);
  static const lightSecondary = Color(0xFF866629);
  static const lightSurfaceContainer = Color(0xFFE8ECEB);
  static const lightSurfaceContainerHigh = Color(0xFFDDE3E2);
  static const onInk = Color(0xFFF3F5F4);
  static const onInkMuted = Color(0xB3F3F5F4);
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

@immutable
class LumaExtras extends ThemeExtension<LumaExtras> {
  const LumaExtras({
    required this.success,
    required this.warning,
    required this.playerInk,
    required this.onPlayerInk,
    required this.onPlayerInkMuted,
    required this.badgeScrim,
    required this.coverRadius,
  });

  final Color success;
  final Color warning;
  final Color playerInk;
  final Color onPlayerInk;
  final Color onPlayerInkMuted;
  final Color badgeScrim;
  final double coverRadius;

  static const light = LumaExtras(
    success: LumaColors.lightSuccess,
    warning: LumaColors.lightWarning,
    playerInk: LumaColors.ink,
    onPlayerInk: LumaColors.onInk,
    onPlayerInkMuted: LumaColors.onInkMuted,
    badgeScrim: Color(0x9A101820),
    coverRadius: LumaRadii.large,
  );

  static const dark = LumaExtras(
    success: LumaColors.success,
    warning: LumaColors.warning,
    playerInk: LumaColors.ink,
    onPlayerInk: LumaColors.onInk,
    onPlayerInkMuted: LumaColors.onInkMuted,
    badgeScrim: Color(0xB3101820),
    coverRadius: LumaRadii.large,
  );

  @override
  LumaExtras copyWith({
    Color? success,
    Color? warning,
    Color? playerInk,
    Color? onPlayerInk,
    Color? onPlayerInkMuted,
    Color? badgeScrim,
    double? coverRadius,
  }) {
    return LumaExtras(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      playerInk: playerInk ?? this.playerInk,
      onPlayerInk: onPlayerInk ?? this.onPlayerInk,
      onPlayerInkMuted: onPlayerInkMuted ?? this.onPlayerInkMuted,
      badgeScrim: badgeScrim ?? this.badgeScrim,
      coverRadius: coverRadius ?? this.coverRadius,
    );
  }

  @override
  LumaExtras lerp(ThemeExtension<LumaExtras>? other, double t) {
    if (other is! LumaExtras) return this;
    return LumaExtras(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      playerInk: Color.lerp(playerInk, other.playerInk, t) ?? playerInk,
      onPlayerInk: Color.lerp(onPlayerInk, other.onPlayerInk, t) ?? onPlayerInk,
      onPlayerInkMuted:
          Color.lerp(onPlayerInkMuted, other.onPlayerInkMuted, t) ??
          onPlayerInkMuted,
      badgeScrim: Color.lerp(badgeScrim, other.badgeScrim, t) ?? badgeScrim,
      coverRadius: t < 0.5 ? coverRadius : other.coverRadius,
    );
  }
}

extension LumaThemeContext on BuildContext {
  LumaExtras get luma => Theme.of(this).extension<LumaExtras>() ?? LumaExtras.light;
}

abstract final class LumaTheme {
  static ThemeData? _dark;
  static ThemeData? _light;

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
          primary: isDark ? LumaColors.darkPrimary : LumaColors.lightPrimary,
          secondary: isDark ? LumaColors.gold : LumaColors.lightSecondary,
          surfaceContainer: isDark
              ? LumaColors.surface
              : LumaColors.lightSurfaceContainer,
          surfaceContainerHigh: isDark
              ? LumaColors.elevated
              : LumaColors.lightSurfaceContainerHigh,
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
      extensions: [extras],
    );

    final textTheme = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.4,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w400,
        height: 1.4,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
      labelMedium: base.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LumaSpacing.md,
          vertical: LumaSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.outlineVariant.withAlpha(100)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusMd,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(LumaLayout.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.lg),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, LumaLayout.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(
            LumaLayout.minTapTarget,
            LumaLayout.minTapTarget,
          ),
          shape: RoundedRectangleBorder(borderRadius: radiusMd),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        side: BorderSide(color: scheme.outlineVariant.withAlpha(80)),
        selectedColor: scheme.primaryContainer,
        labelStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.xs),
        showCheckmark: false,
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.08),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radiusMd),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: LumaSpacing.md),
        ),
        textStyle: WidgetStatePropertyAll(textTheme.bodyLarge),
        hintStyle: WidgetStatePropertyAll(
          textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumaRadii.large),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumaRadii.large),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: LumaLayout.navigationBarHeight,
        backgroundColor: scheme.surface,
        elevation: 0,
        indicatorColor: scheme.primaryContainer.withAlpha(160),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        indicatorColor: scheme.primaryContainer.withAlpha(160),
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LumaSpacing.md,
          vertical: LumaSpacing.xxs,
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.24),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackHeight: 3,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withAlpha(90),
        space: 1,
        thickness: 1,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        elevation: 0,
        highlightElevation: 0,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
