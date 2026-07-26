import 'package:flutter/material.dart';

import 'theme/theme_builder.dart';

export 'theme/theme_extension.dart';
export 'theme/tokens.dart';

abstract final class LumaTheme {
  static ThemeData? _dark;
  static ThemeData? _light;

  static ThemeData dark() => _dark ??= LumaThemeBuilder.build(Brightness.dark);

  static ThemeData light() =>
      _light ??= LumaThemeBuilder.build(Brightness.light);
}
