import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData applyLumaComponentThemes({
  required ThemeData base,
  required ColorScheme scheme,
  required Color scaffold,
  required TextTheme textTheme,
  required BorderRadius radiusMd,
  required RoundedRectangleBorder buttonShape,
}) {
  return base.copyWith(
    textTheme: textTheme,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumaRadii.large),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: scaffold,
      foregroundColor: scheme.onSurface,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      iconTheme: IconThemeData(
        color: scheme.onSurface,
        size: LumaIconSize.action,
      ),
      actionsIconTheme: IconThemeData(
        color: scheme.onSurface,
        size: LumaIconSize.action,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
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
        vertical: LumaSpacing.sm + LumaSpacing.xxs / 2,
      ),
      constraints: const BoxConstraints(minHeight: LumaLayout.inputHeight),
      prefixIconConstraints: const BoxConstraints.tightFor(
        width: LumaLayout.minTapTarget,
        height: LumaLayout.minTapTarget,
      ),
      suffixIconConstraints: const BoxConstraints.tightFor(
        width: LumaLayout.minTapTarget,
        height: LumaLayout.minTapTarget,
      ),
      border: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(
          color: scheme.primary,
          width: LumaStroke.focused,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radiusMd,
        borderSide: BorderSide(color: scheme.error, width: LumaStroke.focused),
      ),
    ),
    // 按钮外观收到 40 高、图标 18，显得秀气；padded 让触控区仍补足 48，
    // 手机与 Windows 触屏都点得准。TV 主题会把高度重新放大到 56。
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, LumaLayout.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: buttonShape,
        textStyle: textTheme.labelLarge,
        iconSize: LumaIconSize.status,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, LumaLayout.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: buttonShape,
        textStyle: textTheme.labelLarge,
        iconSize: LumaIconSize.status,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, LumaLayout.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.sm),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: buttonShape,
        textStyle: textTheme.labelLarge,
        iconSize: LumaIconSize.status,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(
          LumaLayout.buttonHeight,
          LumaLayout.buttonHeight,
        ),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
        iconSize: LumaIconSize.compact,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumaRadii.small),
      ),
      side: BorderSide(color: scheme.outlineVariant),
      selectedColor: scheme.primaryContainer,
      labelStyle: textTheme.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.xs),
      labelPadding: const EdgeInsets.symmetric(horizontal: LumaSpacing.xxs),
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
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumaRadii.large),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: LumaSpacing.md),
      ),
      textStyle: WidgetStatePropertyAll(textTheme.bodyLarge),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
      constraints: const BoxConstraints(minHeight: LumaLayout.inputHeight),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumaRadii.extraLarge),
      ),
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainer,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(LumaRadii.extraLarge),
        ),
      ),
      showDragHandle: true,
      dragHandleColor: scheme.outlineVariant,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: radiusMd),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LumaSpacing.md,
        vertical: LumaSpacing.xs,
      ),
      minVerticalPadding: LumaSpacing.xs,
      iconColor: scheme.onSurfaceVariant,
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
      trackHeight: 4,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
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
