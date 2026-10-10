// TV 表单改版消费者回归：分栏与窄屏、方向键设置操作、弹窗返回和普通端隔离。
// 使用真实页面和内存依赖，视口/依赖均随测试释放；不连接后端或启动原生代理。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/core/theme/tv_theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/features/connection/connection_page.dart';
import 'package:luma/features/connection/widgets/connection_brand_header.dart';
import 'package:luma/features/settings/settings_page.dart';
import 'package:luma/features/settings/widgets/server_settings_card.dart';
import 'package:luma/app/controllers/settings_controller.dart';
import 'package:luma/data/storage/theme_preference_store.dart';
import 'package:luma/features/settings/widgets/theme_mode_button.dart';
import 'package:luma/features/shell/widgets/tv_field_gate.dart';

void main() {
  for (final size in [const Size(1280, 720), const Size(960, 540)]) {
    testWidgets('TV 登录 ${size.width} 将说明与有界字段分栏', (tester) async {
      _viewport(tester, size);
      final dependencies = _dependencies(true);
      addTearDown(dependencies.dispose);
      await _pump(tester, dependencies, const ConnectionPage());
      final intro = tester.getRect(
        find.byKey(const ValueKey('tv-connection-introduction')),
      );
      final fields = tester.getRect(
        find.byKey(const ValueKey('tv-connection-fields')),
      );
      expect(intro.right, lessThan(fields.left));
      expect(fields.width, lessThanOrEqualTo(520.001));
      expect(find.byType(ConnectionBrandHeader), findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      await _press(tester, LogicalKeyboardKey.select);
      expect(
        tester.widget<TextField>(_field('IP 地址')).focusNode!.hasFocus,
        isTrue,
      );
      await _press(tester, LogicalKeyboardKey.escape);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, scale) in [
    (const Size(560, 720), 1.0),
    (const Size(960, 540), 1.6),
  ]) {
    testWidgets('TV 登录窄屏或大字体 ${size.width}/$scale 可滚动到提交', (tester) async {
      _viewport(tester, size);
      final dependencies = _dependencies(true);
      addTearDown(dependencies.dispose);
      await _pump(tester, dependencies, const ConnectionPage(), scale: scale);
      final intro = tester.getRect(
        find.byKey(const ValueKey('tv-connection-introduction')),
      );
      final fields = tester.getRect(
        find.byKey(const ValueKey('tv-connection-fields')),
      );
      expect(intro.bottom, lessThan(fields.top));
      await tester.ensureVisible(find.widgetWithText(FilledButton, '立即连接'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, '立即连接').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV 设置方向键切换主题、编辑别名、取消清理及断开并恢复行焦点', (tester) async {
    _viewport(tester, const Size(960, 540));
    final dependencies = _dependencies(true, connected: true);
    addTearDown(dependencies.dispose);
    await _pump(tester, dependencies, const SettingsPage());
    expect(find.byType(ServerSettingsCard), findsNothing);
    expect(find.byType(ThemeModeButton), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    final before = dependencies.settings.themeMode;
    await _press(tester, LogicalKeyboardKey.select);
    expect(dependencies.settings.themeMode, isNot(before));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_rowFocused(tester, 'alias'), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    await _press(tester, LogicalKeyboardKey.select);
    await tester.enterText(find.byType(TextField), '客厅影库');
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(AlertDialog), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_rowFocused(tester, 'alias'), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_rowFocused(tester, 'cache'), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('清理缓存？'), findsOneWidget);
    expect(Focus.of(tester.element(find.text('取消'))).hasFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(_rowFocused(tester, 'cache'), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_rowFocused(tester, 'about'), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_rowFocused(tester, 'disconnect'), isTrue);
    expect(find.text('断开服务器').hitTestable(), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('断开服务器？'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    expect(dependencies.session.isConnected, isTrue);
    expect(_rowFocused(tester, 'disconnect'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV 设置大字体向下滚动仍可访问全部动作和确认弹窗', (tester) async {
    _viewport(tester, const Size(960, 540));
    final dependencies = _dependencies(true, connected: true);
    addTearDown(dependencies.dispose);
    await _pump(tester, dependencies, const SettingsPage(), scale: 1.6);
    for (final id in ['alias', 'cache', 'about', 'disconnect']) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_rowFocused(tester, id), isTrue);
    }
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.widgetWithText(TextButton, '取消').hitTestable(), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, '断开').hitTestable(),
      findsOneWidget,
    );
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(Focus.of(tester.element(find.text('断开'))).hasFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.select);
    expect(dependencies.session.isConnected, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('普通端 ${size.width} 设置页主题三态写入存储并可恢复', (tester) async {
      _viewport(tester, size);
      final store = _MemoryThemeStore();
      final dependencies = _dependencies(false, connected: true, store: store);
      addTearDown(dependencies.dispose);
      await _pump(tester, dependencies, const ConnectionPage());
      expect(find.byType(ConnectionBrandHeader), findsOneWidget);
      expect(find.byType(TvTextFieldGate), findsNothing);
      await _pump(tester, dependencies, const SettingsPage());
      expect(find.byType(ServerSettingsCard), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-settings-actions')), findsNothing);

      await tester.tap(find.byTooltip('主题：跟随系统'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('主题：深色'), findsOneWidget);
      expect(dependencies.settings.themeMode, ThemeMode.dark);
      expect(store.writes, [ThemeMode.dark]);

      final restored = SettingsController(themeStore: store);
      addTearDown(restored.dispose);
      await restored.restoreThemeMode();
      expect(restored.themeMode, ThemeMode.dark);
      expect(tester.takeException(), isNull);
    });
  }
}

/// 内存主题存储：记录每次写入，读取返回最后一次写入值。
class _MemoryThemeStore implements ThemePreferenceStore {
  final writes = <ThemeMode>[];

  @override
  Future<ThemeMode?> read() async => writes.isEmpty ? null : writes.last;

  @override
  Future<void> write(ThemeMode mode) async => writes.add(mode);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

bool _rowFocused(WidgetTester tester, String id) {
  final surface = find.byKey(ValueKey('tv-settings-$id'));
  final ink = find.descendant(of: surface, matching: find.byType(InkWell));
  return tester.widget<InkWell>(ink).focusNode!.hasFocus;
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

AppDependencies _dependencies(
  bool television, {
  bool connected = false,
  ThemePreferenceStore? store,
}) {
  final dependencies = AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
    themeStore: store,
    deviceProfile: television
        ? AppDeviceProfile.television
        : AppDeviceProfile.standard,
  );
  if (connected) {
    dependencies.session.connect(
      const ServerProfile(
        name: '家庭影库',
        address: 'http://192.168.1.10:8080',
        token: 'test-session',
        hostName: 'living-room',
        sourceCount: 2,
      ),
    );
  }
  return dependencies;
}

Future<void> _pump(
  WidgetTester tester,
  AppDependencies dependencies,
  Widget page, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    AppScope(
      dependencies: dependencies,
      child: ListenableBuilder(
        listenable: dependencies.settings,
        builder: (context, _) {
          final base = switch (dependencies.settings.themeMode) {
            ThemeMode.light => LumaTheme.light(),
            _ => LumaTheme.dark(),
          };
          return MaterialApp(
            theme: dependencies.deviceProfile.isTelevision
                ? applyTvTheme(base)
                : base,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: page,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
