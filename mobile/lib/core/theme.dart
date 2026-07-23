import 'package:flutter/material.dart';

abstract final class LumaColors {
  // Extracted from the app icon: graphite, aged gold, and warm ivory.
  // All Material roles are explicit so a seed color cannot introduce teal
  // containers elsewhere in the app.
  static const ink = Color(0xFF2C3433);
  static const deepBlue = Color(0xFF2E322F);
  static const surface = Color(0xFF3A3D38);
  static const elevated = Color(0xFF484A44);
  static const gold = Color(0xFFB48A4B);
  static const paper = Color(0xFFEEE6DA);
  static const success = Color(0xFF8EAD92);
  static const warning = Color(0xFFC1A064);
  // Darker light-theme semantic colors preserve text/icon contrast on ivory.
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

  /// Roughly one mobile viewport, shared by primary scroll surfaces so they
  /// prebuild enough content for smooth scrolling without retaining pages.
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
    badgeScrim: LumaColors.lightBadgeScrim,
    coverRadius: LumaRadii.large,
  );

  static const dark = LumaExtras(
    success: LumaColors.success,
    warning: LumaColors.warning,
    playerInk: LumaColors.ink,
    onPlayerInk: LumaColors.onInk,
    onPlayerInkMuted: LumaColors.onInkMuted,
    badgeScrim: LumaColors.darkBadgeScrim,
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
  LumaExtras get luma =>
      Theme.of(this).extension<LumaExtras>() ?? LumaExtras.light;
}

abstract final class LumaTheme {
  static ThemeData? _dark;
  static ThemeData? _light;

  static ThemeData dark() => _dark ??= _build(Brightness.dark);

  static ThemeData light() => _light ??= _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
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
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
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
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
        ),
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
