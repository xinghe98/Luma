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

    test('字号阶梯逐级递减、标题与正文分层且字距为 0', () {
      final t = LumaTheme.light().textTheme;
      final scale = [
        t.displayLarge,
        t.displayMedium,
        t.displaySmall,
        t.headlineLarge,
        t.headlineMedium,
        t.headlineSmall,
        t.titleLarge,
      ].map((style) => style!.fontSize!).toList();
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], lessThan(scale[i - 1]), reason: 'level $i');
      }
      // 同字号的标题和正文靠字重区分，避免层级扁平。
      expect(t.titleMedium!.fontWeight, isNot(t.bodyLarge!.fontWeight));
      expect(t.bodyMedium!.height, greaterThanOrEqualTo(1.5));
      for (final style in [t.headlineLarge, t.titleSmall, t.bodyMedium]) {
        expect(style!.letterSpacing, 0);
      }
    });
  });
}
