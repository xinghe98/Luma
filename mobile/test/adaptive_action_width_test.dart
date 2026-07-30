// 验证 AdaptiveActionWidth 与 LumaTheme 在手机和 Windows 宽屏下的按钮宽度，并在测试后还原视口。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/shared/layout/adaptive_action_width.dart';

void main() {
  const cases = <(String, Size, double)>[
    ('手机', Size(390, 844), 358),
    ('Windows 宽屏', Size(1200, 800), LumaLayout.actionMaxWidth),
  ];

  for (final (name, viewport, expectedWidth) in cases) {
    testWidgets('$name下主按钮使用合适宽度', (tester) async {
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: LumaTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
              child: AdaptiveActionWidth(
                child: FilledButton(
                  key: const ValueKey('primary-action'),
                  onPressed: () {},
                  child: const Text('保存设置'),
                ),
              ),
            ),
          ),
        ),
      );

      final buttonRect = tester.getRect(
        find.byKey(const ValueKey('primary-action')),
      );
      expect(buttonRect.width, expectedWidth);
      expect(buttonRect.height, LumaLayout.buttonHeight);
      expect(buttonRect.center.dx, closeTo(viewport.width / 2, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('宽屏短操作可使用更小上限并保持居中', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: LumaTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
            child: AdaptiveActionWidth(
              maxWidth: 240,
              child: FilledButton(
                key: const ValueKey('short-action'),
                onPressed: () {},
                child: const Text('应用'),
              ),
            ),
          ),
        ),
      ),
    );

    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('short-action')),
    );
    expect(buttonRect.width, 240);
    expect(buttonRect.center.dx, 600);
  });

  for (final (name, theme) in [
    ('浅色', LumaTheme.light()),
    ('深色', LumaTheme.dark()),
  ]) {
    testWidgets('$name主题不强制普通按钮占满宽屏', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('intrinsic-action'),
                onPressed: () {},
                child: const Text('确认'),
              ),
            ),
          ),
        ),
      );

      final buttonRect = tester.getRect(
        find.byKey(const ValueKey('intrinsic-action')),
      );
      expect(buttonRect.width, lessThan(200));
      expect(buttonRect.height, LumaLayout.buttonHeight);
    });
  }
}
