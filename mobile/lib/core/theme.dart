// Luma's public theme entry point preserves stable imports for feature widgets.
// Token and implementation modules are re-exported or composed here without exposing build internals.
import 'package:flutter/material.dart';

import 'theme/theme_builder.dart';

export 'theme/theme_extension.dart';
export 'theme/tokens.dart';

abstract final class LumaTheme {
  static ThemeData? _dark;
  static ThemeData? _light;

  /// Returns the cached dark Material theme.
  static ThemeData dark() => _dark ??= LumaThemeBuilder.build(Brightness.dark);

  /// Returns the cached light Material theme.
  static ThemeData light() => _light ??= LumaThemeBuilder.build(Brightness.light);
}
