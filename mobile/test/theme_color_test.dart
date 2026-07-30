// 验证轻影明暗主题的品牌颜色映射和关键文字对比度。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';

void main() {
  group('Luma colors', () {
    test('light theme maps the airy blue palette to Material roles', () {
      final theme = LumaTheme.light();
      final extras = theme.extension<LumaExtras>()!;

      expect(theme.colorScheme.primary, LumaColors.lightPrimary);
      expect(theme.scaffoldBackgroundColor, LumaColors.paper);
      expect(
        theme.colorScheme.primaryContainer,
        LumaColors.lightPrimaryContainer,
      );
      expect(extras.brandSurface, LumaColors.lightBrandSurface);
      expect(extras.brandSurfaceVariant, LumaColors.lightBrandSurfaceVariant);
    });

    test('dark theme maps the blue-black palette to Material roles', () {
      final theme = LumaTheme.dark();
      final extras = theme.extension<LumaExtras>()!;

      expect(theme.colorScheme.primary, LumaColors.darkPrimary);
      expect(theme.scaffoldBackgroundColor, LumaColors.deepBlue);
      expect(extras.brandSurface, LumaColors.darkBrandSurface);
      expect(extras.brandSurfaceVariant, LumaColors.darkBrandSurfaceVariant);
    });

    test('primary actions and brand headers keep readable text contrast', () {
      expect(
        _contrastRatio(LumaColors.lightPrimary, LumaColors.paper),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(LumaColors.darkBrandSurface, LumaColors.onInk),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('controls share the documented size and radius system', () {
      final theme = LumaTheme.light();
      final filledMinimum = theme
          .filledButtonTheme
          .style
          ?.minimumSize
          ?.resolve(<WidgetState>{});
      final iconMinimum = theme
          .iconButtonTheme
          .style
          ?.minimumSize
          ?.resolve(<WidgetState>{});

      expect(theme.inputDecorationTheme.constraints?.minHeight, 52);
      expect(filledMinimum?.height, 52);
      expect(iconMinimum, const Size(48, 48));
      expect(LumaRadii.medium, 16);
      expect(LumaIconSize.action, 24);
    });
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
