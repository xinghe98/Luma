// 对比度护栏：保证明暗主题文字清晰、不刺眼，且不出现纯黑纯白。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';

const _pureBlack = Color(0xFF000000);
const _pureWhite = Color(0xFFFFFFFF);

void main() {
  for (final entry in <String, ThemeData Function()>{
    'light': LumaTheme.light,
    'dark': LumaTheme.dark,
  }.entries) {
    group('${entry.key} theme', () {
      late ThemeData theme;
      late ColorScheme scheme;
      late LumaExtras extras;
      late List<Color> surfaces;

      setUp(() {
        theme = entry.value();
        scheme = theme.colorScheme;
        extras = theme.extension<LumaExtras>()!;
        surfaces = [
          scheme.surface,
          scheme.surfaceContainerLow,
          scheme.surfaceContainer,
          scheme.surfaceContainerHigh,
          scheme.surfaceContainerHighest,
        ];
      });

      test('正文在所有表面上清晰但不炫光', () {
        for (final surface in surfaces) {
          final ratio = _contrastRatio(scheme.onSurface, surface);
          expect(ratio, greaterThanOrEqualTo(7.0), reason: '$surface');
          expect(ratio, lessThanOrEqualTo(16.6), reason: '$surface');
        }
      });

      test('次要文字在所有表面上至少 5.5:1', () {
        for (final surface in surfaces) {
          expect(
            _contrastRatio(scheme.onSurfaceVariant, surface),
            greaterThanOrEqualTo(5.5),
            reason: '$surface',
          );
        }
      });

      test('强调色与状态色可读', () {
        expect(
          _contrastRatio(scheme.primary, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(scheme.error, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(extras.success, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrastRatio(extras.warning, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('容器上的文字至少 7:1', () {
        final pairs = {
          'primary': (scheme.onPrimaryContainer, scheme.primaryContainer),
          'secondary': (scheme.onSecondaryContainer, scheme.secondaryContainer),
          'tertiary': (scheme.onTertiaryContainer, scheme.tertiaryContainer),
          'error': (scheme.onErrorContainer, scheme.errorContainer),
        };
        pairs.forEach((name, pair) {
          expect(
            _contrastRatio(pair.$1, pair.$2),
            greaterThanOrEqualTo(7.0),
            reason: name,
          );
        });
      });

      test('播放器墨色上的文字可读', () {
        expect(
          _contrastRatio(extras.onPlayerInk, extras.playerInk),
          greaterThanOrEqualTo(7.0),
        );
        expect(
          _contrastRatio(extras.onPlayerInkMuted, extras.playerInk),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('页面底和正文不使用纯黑纯白', () {
        for (final color in [scheme.surface, scheme.onSurface]) {
          expect(color, isNot(_pureBlack));
          expect(color, isNot(_pureWhite));
        }
      });

      test('按钮外观紧凑但触控区补足 48dp', () {
        final filled = theme.filledButtonTheme.style!;
        final icon = theme.iconButtonTheme.style!;
        expect(filled.tapTargetSize, MaterialTapTargetSize.padded);
        expect(icon.tapTargetSize, MaterialTapTargetSize.padded);
        expect(
          filled.minimumSize?.resolve(<WidgetState>{})?.height,
          lessThan(LumaLayout.minTapTarget),
        );
      });
    });
  }
}

double _contrastRatio(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}
