// 复现 TV 许可居中段落、选项首帧可见性、确认键重复与组件字号回归。
// 通过 AppScope、真实弹窗与 Luma 主题消费数据；依赖、视口和许可注册在用例后释放。
// 手机与宽屏保留触摸/键盘路径，字号断言读取实际 RenderParagraph。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/core/theme/tv_theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/features/settings/dialogs/about_luma_dialog.dart';
import 'package:luma/shared/interaction/tv_key_bindings.dart';
import 'package:luma/shared/widgets/single_choice_sheet.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('TV ${brightness.name} 许可居中哨兵显示居中文字且无负缩进', (tester) async {
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      LicenseRegistry.addLicense(() => Stream.value(const _CenteredLicense()));
      await _pumpHost(
        tester,
        brightness: brightness,
        profile: AppDeviceProfile.television,
        size: const Size(1280, 720),
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showAboutLumaDialog(context),
            child: const Text('关于入口'),
          ),
        ),
      );
      await tester.tap(find.text('关于入口'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开源许可'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final heading = find.text(_CenteredLicense.heading);
      expect(heading, findsOneWidget);
      final paragraph = _paragraph(tester, _CenteredLicense.heading);
      expect(paragraph.textAlign, TextAlign.center);
      expect(heading.hitTestable(), findsOneWidget);
      final insets = find.ancestor(of: heading, matching: find.byType(Padding));
      for (final padding in tester.widgetList<Padding>(insets)) {
        final resolved = padding.padding.resolve(TextDirection.ltr);
        expect(resolved.left, greaterThanOrEqualTo(0));
        expect(resolved.right, greaterThanOrEqualTo(0));
      }
      final headingRect = tester.getRect(heading);
      final listRect = tester.getRect(find.byType(ListView));
      expect(headingRect.center.dx, closeTo(listRect.center.dx, 1));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // 返回后实际按钮重新获焦，下一次 OK 可重新进入许可页。
      expect(Focus.of(tester.element(find.text('开源许可'))).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text(_CenteredLicense.heading), findsOneWidget);
    });

    testWidgets('TV ${brightness.name} 960x540 大字倍速末项首帧可见并可遥控选择', (
      tester,
    ) async {
      final results = <double>[];
      await _pumpHost(
        tester,
        brightness: brightness,
        profile: AppDeviceProfile.television,
        size: const Size(960, 540),
        textScale: 1.5,
        child: _ChoiceTrigger(selected: 2.0, onSelected: results.add),
      );
      await tester.tap(find.text('调整速度'));
      await tester.pumpAndSettle();

      final selected = find.widgetWithText(ListTile, '2.0x');
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final selectedRect = tester.getRect(selected);
      expect(selectedRect.top, greaterThanOrEqualTo(viewport.top - 1));
      expect(selectedRect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      expect(find.text('2.0x').hitTestable(), findsOneWidget);
      expect(Focus.of(tester.element(find.text('2.0x'))).hasFocus, isTrue);
      expect(tester.takeException(), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(find.text('1.5x'))).hasFocus, isTrue);
      expect(find.text('1.5x').hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(results, [1.5]);
      expect(find.byType(Dialog), findsNothing);
    });

    for (final key in [
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
    ]) {
      testWidgets('TV ${brightness.name} ${key.keyLabel} 开窗长按只在新按下时选择', (
        tester,
      ) async {
        final results = <double>[];
        await _pumpHost(
          tester,
          brightness: brightness,
          profile: AppDeviceProfile.television,
          size: const Size(1280, 720),
          child: _ChoiceTrigger(selected: 1.0, onSelected: results.add),
        );
        expect(Focus.of(tester.element(find.text('调整速度'))).hasFocus, isTrue);
        await tester.sendKeyDownEvent(key);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(Focus.of(tester.element(find.text('1.0x'))).hasFocus, isTrue);
        await tester.sendKeyRepeatEvent(key);
        await tester.pumpAndSettle();
        await tester.sendKeyRepeatEvent(key);
        await tester.pumpAndSettle();
        // 先释放键再断言，失败也不把按住状态泄漏给后续用例。
        await tester.sendKeyUpEvent(key);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(results, isEmpty);
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(results, [1.0]);
        expect(find.byType(Dialog), findsNothing);
        expect(Focus.of(tester.element(find.text('调整速度'))).hasFocus, isTrue);
      });
    }

    for (final size in [const Size(390, 844), const Size(1280, 720)]) {
      testWidgets('普通端 ${brightness.name} ${size.width} 选项支持触摸与键盘', (
        tester,
      ) async {
        final results = <double>[];
        await _pumpHost(
          tester,
          brightness: brightness,
          profile: AppDeviceProfile.standard,
          size: size,
          child: _ChoiceTrigger(selected: 1.0, onSelected: results.add),
        );
        await tester.tap(find.text('调整速度'));
        await tester.pumpAndSettle();
        expect(
          size.width < LumaLayout.navigationRailBreakpoint
              ? find.byType(BottomSheet)
              : find.byType(Dialog),
          findsOneWidget,
        );
        await tester.tap(find.text('1.25x'));
        await tester.pumpAndSettle();
        expect(results, [1.25]);
        await tester.tap(find.text('调整速度'));
        await tester.pumpAndSettle();
        final target = find.text('1.5x');
        for (var i = 0; i < 7; i++) {
          if (Focus.of(tester.element(target)).hasFocus) break;
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        }
        expect(Focus.of(tester.element(target)).hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(results, [1.25, 1.5]);
        expect(tester.takeException(), isNull);
      });
    }

    for (final scenario in [
      (profile: AppDeviceProfile.television, size: const Size(1280, 720)),
      (profile: AppDeviceProfile.standard, size: const Size(390, 844)),
      (profile: AppDeviceProfile.standard, size: const Size(1280, 720)),
    ]) {
      testWidgets(
        '${scenario.profile.name} ${brightness.name} ${scenario.size.width} '
        '按钮列表与对话框实际渲染字号',
        (tester) async {
          await _pumpHost(
            tester,
            brightness: brightness,
            profile: scenario.profile,
            size: scenario.size,
            child: const _TypographyControls(),
          );
          final textTheme = Theme.of(
            tester.element(find.text('主按钮')),
          ).textTheme;
          for (final label in ['主按钮', '描边按钮', '文本按钮']) {
            expect(
              _paragraph(tester, label).text.style?.fontSize,
              textTheme.labelLarge?.fontSize,
            );
          }
          expect(
            _paragraph(tester, '列表标题').text.style?.fontSize,
            textTheme.titleMedium?.fontSize,
          );
          expect(
            _paragraph(tester, '列表说明').text.style?.fontSize,
            textTheme.bodySmall?.fontSize,
          );
          final scheme = Theme.of(
            tester.element(find.text('列表标题')),
          ).colorScheme;
          expect(
            _paragraph(tester, '列表标题').text.style?.color,
            scheme.onSurface,
          );
          expect(
            _paragraph(tester, '列表说明').text.style?.color,
            scheme.onSurfaceVariant,
          );
          await tester.tap(find.text('主按钮'));
          await tester.pumpAndSettle();
          expect(
            _paragraph(tester, '确认标题').text.style?.fontSize,
            textTheme.titleLarge?.fontSize,
          );
          expect(
            _paragraph(tester, '确认内容').text.style?.fontSize,
            textTheme.bodyMedium?.fontSize,
          );
          expect(
            _paragraph(tester, '确认标题').text.style?.color,
            scheme.onSurface,
          );
          expect(
            _paragraph(tester, '确认内容').text.style?.color,
            scheme.onSurfaceVariant,
          );
          await tester.tap(find.text('关闭确认'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required Brightness brightness,
  required AppDeviceProfile profile,
  required Size size,
  required Widget child,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dependencies = AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
    deviceProfile: profile,
  );
  addTearDown(dependencies.dispose);
  final base = brightness == Brightness.dark
      ? LumaTheme.dark()
      : LumaTheme.light();
  await tester.pumpWidget(
    AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: profile.isTelevision ? applyTvTheme(base) : base,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        // 与生产壳层一致：快捷键只包住首页，不能替弹窗补上路由自己的绑定。
        home: Scaffold(
          body: Center(
            child: profile.isTelevision ? TvKeyBindings(child: child) : child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RenderParagraph _paragraph(WidgetTester tester, String label) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(label), matching: find.byType(RichText)),
    );

class _CenteredLicense extends LicenseEntry {
  const _CenteredLicense();

  static const heading = 'Apache License 居中标题';

  @override
  Iterable<String> get packages => const ['centered_license_package'];

  @override
  Iterable<LicenseParagraph> get paragraphs => const [
    LicenseParagraph(heading, LicenseParagraph.centeredIndent),
    LicenseParagraph('许可正文保留普通左对齐。', 0),
  ];
}

class _ChoiceTrigger extends StatelessWidget {
  const _ChoiceTrigger({required this.selected, required this.onSelected});

  final double selected;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) => FilledButton(
    autofocus: true,
    onPressed: () async {
      final value = await showSingleChoiceSheet<double>(
        context,
        title: '播放速度',
        supportingText: '选择当前视频的播放速度',
        selectedValue: selected,
        choices: [
          for (final speed in [0.5, 1.0, 1.25, 1.5, 2.0])
            BottomSheetChoice(
              value: speed,
              label: '${speed}x',
              icon: Icons.speed_rounded,
            ),
        ],
      );
      if (value != null) onSelected(value);
    },
    child: const Text('调整速度'),
  );
}

class _TypographyControls extends StatelessWidget {
  const _TypographyControls();

  @override
  Widget build(BuildContext context) {
    void openDialog() {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认标题'),
          content: const Text('确认内容'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭确认'),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(onPressed: openDialog, child: const Text('主按钮')),
        OutlinedButton(onPressed: openDialog, child: const Text('描边按钮')),
        TextButton(onPressed: openDialog, child: const Text('文本按钮')),
        ListTile(
          title: const Text('列表标题'),
          subtitle: const Text('列表说明'),
          onTap: openDialog,
        ),
      ],
    );
  }
}
