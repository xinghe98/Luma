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
  });

  final Color success;
  final Color warning;
  final Color playerInk;
  final Color onPlayerInk;
  final Color onPlayerInkMuted;
  final Color badgeScrim;

  static const light = LumaExtras(
    success: LumaColors.lightSuccess,
    warning: LumaColors.lightWarning,
    playerInk: LumaColors.playerInk,
    onPlayerInk: LumaColors.onPlayerInk,
    onPlayerInkMuted: LumaColors.onPlayerInkMuted,
    badgeScrim: LumaColors.badgeScrim,
  );

  static const dark = LumaExtras(
    success: LumaColors.darkSuccess,
    warning: LumaColors.darkWarning,
    playerInk: LumaColors.playerInk,
    onPlayerInk: LumaColors.onPlayerInk,
    onPlayerInkMuted: LumaColors.onPlayerInkMuted,
    badgeScrim: LumaColors.badgeScrim,
  );

  @override
  LumaExtras copyWith({
    Color? success,
    Color? warning,
    Color? playerInk,
    Color? onPlayerInk,
    Color? onPlayerInkMuted,
    Color? badgeScrim,
  }) {
    return LumaExtras(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      playerInk: playerInk ?? this.playerInk,
      onPlayerInk: onPlayerInk ?? this.onPlayerInk,
      onPlayerInkMuted: onPlayerInkMuted ?? this.onPlayerInkMuted,
      badgeScrim: badgeScrim ?? this.badgeScrim,
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
    );
  }
}

extension LumaThemeContext on BuildContext {
  LumaExtras get luma =>
      Theme.of(this).extension<LumaExtras>() ?? LumaExtras.light;
}
