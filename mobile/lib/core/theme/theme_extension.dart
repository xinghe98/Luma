import 'package:flutter/material.dart';

import 'tokens.dart';

/// 补充 Material 色板未覆盖的轻影视觉语义，不承载业务状态。
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
    required this.brandSurface,
    required this.brandSurfaceVariant,
    required this.onBrandSurface,
    required this.onBrandSurfaceMuted,
  });

  final Color success;
  final Color warning;
  final Color playerInk;
  final Color onPlayerInk;
  final Color onPlayerInkMuted;
  final Color badgeScrim;
  final double coverRadius;
  final Color brandSurface;
  final Color brandSurfaceVariant;
  final Color onBrandSurface;
  final Color onBrandSurfaceMuted;

  static const light = LumaExtras(
    success: LumaColors.lightSuccess,
    warning: LumaColors.lightWarning,
    playerInk: LumaColors.ink,
    onPlayerInk: LumaColors.onInk,
    onPlayerInkMuted: LumaColors.onInkMuted,
    badgeScrim: LumaColors.lightBadgeScrim,
    coverRadius: LumaRadii.large,
    brandSurface: LumaColors.lightBrandSurface,
    brandSurfaceVariant: LumaColors.lightBrandSurfaceVariant,
    onBrandSurface: LumaColors.ink,
    onBrandSurfaceMuted: LumaColors.lightOutline,
  );

  static const dark = LumaExtras(
    success: LumaColors.success,
    warning: LumaColors.warning,
    playerInk: LumaColors.ink,
    onPlayerInk: LumaColors.onInk,
    onPlayerInkMuted: LumaColors.onInkMuted,
    badgeScrim: LumaColors.darkBadgeScrim,
    coverRadius: LumaRadii.large,
    brandSurface: LumaColors.darkBrandSurface,
    brandSurfaceVariant: LumaColors.darkBrandSurfaceVariant,
    onBrandSurface: LumaColors.onInk,
    onBrandSurfaceMuted: LumaColors.onInkMuted,
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
    Color? brandSurface,
    Color? brandSurfaceVariant,
    Color? onBrandSurface,
    Color? onBrandSurfaceMuted,
  }) {
    return LumaExtras(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      playerInk: playerInk ?? this.playerInk,
      onPlayerInk: onPlayerInk ?? this.onPlayerInk,
      onPlayerInkMuted: onPlayerInkMuted ?? this.onPlayerInkMuted,
      badgeScrim: badgeScrim ?? this.badgeScrim,
      coverRadius: coverRadius ?? this.coverRadius,
      brandSurface: brandSurface ?? this.brandSurface,
      brandSurfaceVariant: brandSurfaceVariant ?? this.brandSurfaceVariant,
      onBrandSurface: onBrandSurface ?? this.onBrandSurface,
      onBrandSurfaceMuted: onBrandSurfaceMuted ?? this.onBrandSurfaceMuted,
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
      brandSurface:
          Color.lerp(brandSurface, other.brandSurface, t) ?? brandSurface,
      brandSurfaceVariant:
          Color.lerp(brandSurfaceVariant, other.brandSurfaceVariant, t) ??
          brandSurfaceVariant,
      onBrandSurface:
          Color.lerp(onBrandSurface, other.onBrandSurface, t) ?? onBrandSurface,
      onBrandSurfaceMuted:
          Color.lerp(onBrandSurfaceMuted, other.onBrandSurfaceMuted, t) ??
          onBrandSurfaceMuted,
    );
  }
}

extension LumaThemeContext on BuildContext {
  LumaExtras get luma =>
      Theme.of(this).extension<LumaExtras>() ?? LumaExtras.light;
}
