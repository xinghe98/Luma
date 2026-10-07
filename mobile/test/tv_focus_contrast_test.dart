// 锁定 TV 焦点外观：主题色按钮靠填充明度区分落点，描边留在文字和封面外面。
// 不启动设备配置或网络，只泵独立的主题和可聚焦表面。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/core/theme/tv_theme.dart';
import 'package:luma/shared/interaction/luma_focusable_surface.dart';

void main() {
  testWidgets('TV 主题色按钮获焦后填充和文字一起翻色', (tester) async {
    for (final dark in [true, false]) {
      final base = dark ? LumaTheme.dark() : LumaTheme.light();
      final scheme = base.colorScheme;
      final resting = FocusNode();
      final focused = FocusNode();
      addTearDown(resting.dispose);
      addTearDown(focused.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: applyTvTheme(base),
          home: Scaffold(
            body: Row(
              children: [
                FilledButton(
                  focusNode: resting,
                  onPressed: () {},
                  child: const Text('静止'),
                ),
                FilledButton(
                  focusNode: focused,
                  onPressed: () {},
                  child: const Text('获焦'),
                ),
              ],
            ),
          ),
        ),
      );
      focused.requestFocus();
      await tester.pumpAndSettle();

      final restingFill = _material(
        tester,
        find.widgetWithText(FilledButton, '静止'),
      );
      final focusedFill = _material(
        tester,
        find.widgetWithText(FilledButton, '获焦'),
      );
      expect(restingFill.color, scheme.primaryContainer);
      expect(focusedFill.color, scheme.primary);
      expect(restingFill.textStyle?.color, scheme.onPrimaryContainer);
      expect(focusedFill.textStyle?.color, scheme.onPrimary);
      expect(
        (scheme.primary.computeLuminance() -
                scheme.primaryContainer.computeLuminance())
            .abs(),
        greaterThan(0.3),
      );
      final ring = (focusedFill.shape! as OutlinedBorder).side;
      expect(ring.width, LumaTvLayout.focusStroke);
      expect(
        ring.color,
        scheme.primary.computeLuminance() > 0.45
            ? scheme.surface
            : scheme.onSurface,
      );
    }
  });

  testWidgets('TV 描边和文本按钮获焦才铺上主题色', (tester) async {
    final scheme = LumaTheme.dark().colorScheme;
    final outlined = FocusNode();
    final text = FocusNode();
    final icon = FocusNode();
    addTearDown(outlined.dispose);
    addTearDown(text.dispose);
    addTearDown(icon.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: applyTvTheme(LumaTheme.dark()),
        home: Scaffold(
          body: Column(
            children: [
              OutlinedButton(
                focusNode: outlined,
                onPressed: () {},
                child: const Text('描边'),
              ),
              TextButton(
                focusNode: text,
                onPressed: () {},
                child: const Text('文本'),
              ),
              IconButton(
                focusNode: icon,
                onPressed: () {},
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
      ),
    );

    final outlinedRest = _material(
      tester,
      find.widgetWithText(OutlinedButton, '描边'),
    );
    expect(outlinedRest.color, Colors.transparent);
    outlined.requestFocus();
    await tester.pumpAndSettle();
    final outlinedFocus = _material(
      tester,
      find.widgetWithText(OutlinedButton, '描边'),
    );
    expect(outlinedFocus.color, scheme.primary);
    expect(outlinedFocus.textStyle?.color, scheme.onPrimary);

    text.requestFocus();
    await tester.pumpAndSettle();
    expect(
      _material(tester, find.widgetWithText(TextButton, '文本')).color,
      scheme.primary,
    );

    icon.requestFocus();
    await tester.pumpAndSettle();
    expect(
      _material(tester, find.byType(IconButton)).color,
      scheme.inverseSurface,
    );
  });

  testWidgets('普通主题按钮获焦不改填充色', (tester) async {
    final scheme = LumaTheme.dark().colorScheme;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: LumaTheme.dark(),
        home: Scaffold(
          body: FilledButton(
            focusNode: node,
            onPressed: () {},
            child: const Text('保存'),
          ),
        ),
      ),
    );
    final before = _material(tester, find.byType(FilledButton)).color;
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(_material(tester, find.byType(FilledButton)).color, before);
    expect(before, scheme.primary);
  });

  testWidgets('TV 卡片焦点描边留在文字和封面外面', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: applyTvTheme(LumaTheme.dark()),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: LumaFocusableSurface(
              label: '第 1 集',
              onActivate: () {},
              borderRadius: BorderRadius.circular(LumaRadii.small),
              focusBorderWidth: LumaTvLayout.focusStroke,
              focusNode: node,
              child: const Column(
                children: [
                  SizedBox(
                    height: 72,
                    width: double.infinity,
                    child: TvArtworkFocus(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      child: ColoredBox(
                        key: ValueKey('poster'),
                        color: Color(0xFF335577),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                  Text('第 1 集 · 会被白边挡住的标题'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();

    final surface = tester.getRect(find.byType(LumaFocusableSurface));
    final title = tester.getRect(find.text('第 1 集 · 会被白边挡住的标题'));
    const stroke = LumaTvLayout.focusStroke;
    expect(title.left, greaterThanOrEqualTo(surface.left + stroke - 0.1));
    expect(title.right, lessThanOrEqualTo(surface.right - stroke + 0.1));
    expect(title.bottom, lessThanOrEqualTo(surface.bottom - stroke + 0.1));

    final poster = tester.getRect(find.byKey(const ValueKey('poster')));
    final frame = tester.getRect(find.byType(TvArtworkFocus));
    expect(poster.left, closeTo(frame.left + stroke, 0.5));
    expect(poster.top, closeTo(frame.top + stroke, 0.5));
    expect(poster.right, closeTo(frame.right - stroke, 0.5));
    expect(poster.bottom, closeTo(frame.bottom - stroke, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度描边不额外撑开卡片', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LumaFocusableSurface(
            label: '手机卡片',
            onActivate: _noop,
            borderRadius: BorderRadius.all(Radius.circular(12)),
            focusBorderWidth: 2,
            child: Text('手机标题'),
          ),
        ),
      ),
    );
    final surface = tester.getRect(find.byType(LumaFocusableSurface));
    final title = tester.getRect(find.text('手机标题'));
    expect(title.top, closeTo(surface.top, 0.5));
    expect(title.left, closeTo(surface.left, 0.5));
  });
}

void _noop() {}

Material _material(WidgetTester tester, Finder button) {
  return tester.widget<Material>(
    find.descendant(of: button, matching: find.byType(Material)).first,
  );
}
