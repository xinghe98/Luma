// Luma theme extensions expose semantic artwork colors beyond Material's color scheme.
// They are installed by LumaThemeBuilder and read by widgets through BuildContext.
import 'package:flutter/material.dart';

import 'tokens.dart';

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


