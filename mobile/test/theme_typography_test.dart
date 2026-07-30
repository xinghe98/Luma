import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';

void main() {
  group('Luma typography', () {
    test('light and dark themes use MiSans with system fallback', () {
      for (final theme in [LumaTheme.light(), LumaTheme.dark()]) {
        expect(
          theme.textTheme.bodyMedium?.fontFamily,
          LumaTypography.fontFamily,
        );
        expect(
          theme.textTheme.bodyMedium?.fontFamilyFallback,
          LumaTypography.fontFamilyFallback,
        );
      }
    });

    test('type roles use intentional sizes, weights, and zero tracking', () {
      final textTheme = LumaTheme.light().textTheme;

      expect(textTheme.displayLarge?.fontSize, 40);
      expect(textTheme.headlineLarge?.fontSize, 32);
      expect(textTheme.headlineLarge?.fontWeight, FontWeight.w700);
      expect(textTheme.titleLarge?.fontSize, 20);
      expect(textTheme.titleMedium?.fontWeight, FontWeight.w500);
      expect(textTheme.bodyLarge?.fontSize, 16);
      expect(textTheme.bodyMedium?.height, 1.5);
      expect(textTheme.labelLarge?.fontWeight, FontWeight.w600);
      expect(textTheme.labelSmall?.fontSize, 11);
      expect(textTheme.headlineLarge?.letterSpacing, 0);
      expect(textTheme.titleSmall?.letterSpacing, 0);
    });
  });
}
