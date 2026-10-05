// 表单回归：真实字段闸门、搜索框、代理弹窗和连接页协作处理遥控器与 IME。
// 沿用 proxy_widget_test 的内存存储/native 桩；每例释放依赖、节点并还原窗口和剪贴板通道。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/proxy/proxy_profile_store.dart';
import 'package:luma/data/proxy/proxy_route.dart';
import 'package:luma/data/proxy/vmess_proxy_controller.dart';
import 'package:luma/data/proxy/vmess_proxy_profile.dart';
import 'package:luma/data/proxy/xray_bridge.dart';
import 'package:luma/data/services/connection_service.dart';
import 'package:luma/features/connection/connection_page.dart';
import 'package:luma/features/connection/widgets/vmess_proxy_control.dart';
import 'package:luma/features/search/widgets/search_input.dart';
import 'package:luma/features/shell/widgets/tv_field_gate.dart';
import 'package:luma/shared/interaction/tv_key_bindings.dart';

void main() {
  for (final (name, key, brightness) in [
    ('Select', LogicalKeyboardKey.select, Brightness.light),
    ('Enter', LogicalKeyboardKey.enter, Brightness.dark),
  ]) {
    testWidgets('TV 搜索清除按钮响应 $name 且不进入编辑', (tester) async {
      _viewport(tester, const Size(1280, 720));
      final text = TextEditingController(text: '星际旅行');
      final field = FocusNode(skipTraversal: true);
      addTearDown(text.dispose);
      addTearDown(field.dispose);
      var clears = 0;
      await tester.pumpWidget(
        _searchApp(
          text: text,
          field: field,
          television: true,
          brightness: brightness,
          onClear: () {
            clears++;
            text.clear();
          },
        ),
      );
      await tester.pumpAndSettle();
      await _focusIcon(tester, Icons.close_rounded);
      expect(tester.testTextInput.isVisible, isFalse);

      await _heldConfirm(tester, key);

      expect(text.text, isEmpty);
      expect(clears, 1);
      expect(find.byTooltip('清除'), findsNothing);
      expect(find.text('搜索标题、标签或格式'), findsOneWidget);
      expect(field.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });
  }

  for (final (name, key, replacing) in [
    ('Select 首次录入', LogicalKeyboardKey.select, false),
    ('Enter 更换节点', LogicalKeyboardKey.enter, true),
  ]) {
    testWidgets('TV VMess 粘贴按钮响应 $name 且长按只读一次剪贴板', (tester) async {
      _viewport(tester, const Size(1280, 720));
      final native = _WidgetNative();
      final bridge = XrayBridge(rawInvoker: native.invoke);
      final proxy = VmessProxyController(
        store: _MemoryProxyProfileStore(),
        parser: VmessProfileParser(bridge),
        bridge: bridge,
        route: ProxyRoute(),
        portProbe: (_) async => true,
      );
      try {
        await proxy.load();
        if (replacing) await proxy.importFromClipboard('vmess://old-node');
        final dependencies = _dependencies(television: true);
        addTearDown(dependencies.dispose);
        var clipboardReads = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.getData') {
              clipboardReads++;
              return <String, dynamic>{'text': 'vmess://replacement-node'};
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        await tester.pumpWidget(
          AppScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: LumaTheme.dark(),
              builder: (context, child) => TvKeyBindings(child: child!),
              home: Scaffold(
                appBar: AppBar(
                  actions: [
                    VmessProxyAppBarAction(
                      controller: proxy,
                      enabled: true,
                      onStart: () async {
                        await proxy.start();
                        return proxy.isActive;
                      },
                      onStop: proxy.stop,
                      onImport: proxy.importFromClipboard,
                      onDelete: proxy.deleteProfile,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('代理'));
        await tester.pumpAndSettle();
        if (replacing) {
          await tester.tap(find.text('更换节点'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '保存并启动'),
                )
                .onPressed,
            isNull,
          );
        }
        await _focusIcon(tester, Icons.content_paste_rounded);
        await _heldConfirm(tester, key);

        expect(clipboardReads, 1);
        expect(
          find.widgetWithText(TextField, 'vmess://replacement-node'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isFalse,
        );
        expect(tester.testTextInput.isVisible, isFalse);
        final save = find.widgetWithText(FilledButton, '保存并启动');
        expect(save.hitTestable(), findsOneWidget);
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        expect(find.byType(AlertDialog), findsOneWidget);
      } finally {
        // 桥的串行 Future 属于测试的假时钟；在测试体内清空，避免 tearDown 等待停滞。
        await tester.pumpWidget(const SizedBox.shrink());
        await proxy.disposeProxy();
      }
    });
  }

  for (final (result, message) in [
    (ConnectionResult.unauthorized, '用户名或密码错误，或账号已停用'),
    (ConnectionResult.unreachable, '无法连接服务器，请检查地址和内网状态'),
  ]) {
    testWidgets('TV 延迟 ${result.name} 在加载后把焦点还给可见连接按钮并保留输入', (tester) async {
      _viewport(tester, const Size(1280, 720));
      final service = _PendingConnectionService();
      final dependencies = _dependencies(television: true, service: service);
      addTearDown(dependencies.dispose);
      await _pumpConnection(tester, dependencies);
      await _fillConnection(tester);
      final connect = find.widgetWithText(FilledButton, '立即连接');
      await tester.ensureVisible(connect);
      tester.widget<FilledButton>(connect).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      // 必须先真正绘制禁用态，才能覆盖异步完成早于按钮重新启用的窗口。
      await tester.pump();
      final loading = find.widgetWithText(FilledButton, '正在连接');
      expect(loading.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(loading).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(service.requests.length, 1);

      service.requests.single.complete(result);
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(connect.hitTestable(), findsOneWidget);
      final button = tester.widget<FilledButton>(connect);
      expect(button.onPressed, isNotNull);
      expect(button.focusNode!.hasPrimaryFocus, isTrue);
      expect(_text(tester, 'IP 地址'), '192.168.1.20');
      expect(_text(tester, '端口'), '8096');
      expect(_text(tester, '用户名'), 'alice');
      expect(_text(tester, '密码'), 'retained-password');
      expect(tester.testTextInput.isVisible, isFalse);
      // 焦点不仅存在，还能直接再按 OK 重试。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(service.requests.length, 2);
      expect(find.text('正在连接'), findsOneWidget);
      service.requests.last.complete(result);
      await tester.pumpAndSettle();
    });
  }

  testWidgets('TV 字段 OK 进入编辑，Back 退出编辑，IME Next 和 Done 只提交一次', (tester) async {
    _viewport(tester, const Size(1280, 720));
    final service = _PendingConnectionService();
    final dependencies = _dependencies(television: true, service: service);
    addTearDown(dependencies.dispose);
    await _pumpConnection(tester, dependencies);
    expect(tester.testTextInput.isVisible, isFalse);

    await _heldConfirm(tester, LogicalKeyboardKey.select);
    expect(_editing(tester, 'IP 地址'), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(service.requests, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_editing(tester, 'IP 地址'), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byType(ConnectionPage), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_editing(tester, 'IP 地址'), isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_editing(tester, 'IP 地址'), isFalse);
    expect(find.byType(ConnectionPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('192.168.1.20');
    for (final (label, value) in [
      ('端口', '8096'),
      ('用户名', 'alice'),
      ('密码', 'retained-password'),
    ]) {
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(_editing(tester, label), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText(value);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(service.requests.length, 1);
    expect(find.text('正在连接'), findsOneWidget);
    service.requests.single.complete(ConnectionResult.unauthorized);
    await tester.pumpAndSettle();
  });

  for (final (name, size, brightness) in [
    ('手机', const Size(390, 844), Brightness.light),
    ('宽屏', const Size(1200, 800), Brightness.dark),
  ]) {
    testWidgets('$name 搜索可直接点按编辑和清除，连接表单直接编辑并 Done 提交', (tester) async {
      _viewport(tester, size);
      final text = TextEditingController();
      final field = FocusNode();
      addTearDown(text.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _searchApp(
          text: text,
          field: field,
          television: false,
          brightness: brightness,
          onClear: text.clear,
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(field.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('直接输入');
      await tester.pump();
      await tester.tap(find.byTooltip('清除'));
      await tester.pumpAndSettle();
      expect(text.text, isEmpty);
      expect(find.byType(TvTextFieldGate), findsNothing);

      final service = _PendingConnectionService();
      final dependencies = _dependencies(television: false, service: service);
      addTearDown(dependencies.dispose);
      await _pumpConnection(tester, dependencies, brightness: brightness);
      await tester.tap(_field('IP 地址'));
      await tester.pumpAndSettle();
      expect(_editing(tester, 'IP 地址'), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await _fillConnection(tester);
      expect(find.byType(TvTextFieldGate), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(service.requests.length, 1);
      expect(find.text('正在连接'), findsOneWidget);
      service.requests.single.complete(ConnectionResult.unauthorized);
      await tester.pumpAndSettle();
      expect(_text(tester, '密码'), 'retained-password');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '立即连接'))
            .onPressed,
        isNotNull,
      );
    });
  }
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _heldConfirm(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.pump();
  await tester.sendKeyRepeatEvent(key);
  await tester.sendKeyRepeatEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _focusIcon(WidgetTester tester, IconData icon) async {
  final control = find.byIcon(icon);
  expect(control.hitTestable(), findsOneWidget);
  final focus = Focus.of(tester.element(control));
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue);
}

Widget _searchApp({
  required TextEditingController text,
  required FocusNode field,
  required bool television,
  required Brightness brightness,
  required VoidCallback onClear,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? LumaTheme.dark() : LumaTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: ListenableBuilder(
            listenable: text,
            builder: (context, _) {
              Widget input(bool focused) => SearchInput(
                textController: text,
                focusNode: field,
                television: focused,
                onChanged: (_) {},
                onSubmitted: (_) {},
                onClear: onClear,
              );
              return television
                  ? TvKeyBindings(
                      child: TvTextFieldGate(
                        fieldFocusNode: field,
                        autofocus: true,
                        builder: (context, focused) => input(focused),
                      ),
                    )
                  : input(false);
            },
          ),
        ),
      ),
    ),
  );
}

AppDependencies _dependencies({
  required bool television,
  _PendingConnectionService? service,
}) => AppDependencies(
  mediaRepository: MockMediaRepository(),
  connectionService: service ?? _PendingConnectionService(),
  deviceProfile: television
      ? AppDeviceProfile.television
      : AppDeviceProfile.standard,
);

Future<void> _pumpConnection(
  WidgetTester tester,
  AppDependencies dependencies, {
  Brightness brightness = Brightness.dark,
}) async {
  await tester.pumpWidget(
    AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? LumaTheme.dark()
            : LumaTheme.light(),
        home: const ConnectionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

bool _editing(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).focusNode!.hasFocus;

Future<void> _fillConnection(WidgetTester tester) async {
  for (final (label, value) in [
    ('IP 地址', '192.168.1.20'),
    ('端口', '8096'),
    ('用户名', 'alice'),
    ('密码', 'retained-password'),
  ]) {
    await tester.ensureVisible(_field(label));
    await tester.enterText(_field(label), value);
  }
}

final class _PendingConnectionService implements ConnectionService {
  final requests = <Completer<ConnectionResult>>[];

  @override
  ServerProfile? get connectedProfile => null;

  @override
  Future<ConnectionResult> login(String address, LoginCredentials credentials) {
    final request = Completer<ConnectionResult>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<ConnectionResult> restore(String address, String sessionToken) async =>
      ConnectionResult.unauthorized;

  @override
  Future<void> disconnect() async {}
}

final class _MemoryProxyProfileStore implements ProxyProfileStore {
  VmessProxyProfile? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<VmessProxyProfile?> read() async => value;

  @override
  Future<void> write(VmessProxyProfile profile) async => value = profile;
}

// 与已有代理组件测试相同的解析桩；这里不启动真实 native 服务。
final class _WidgetNative {
  Future<String> invoke(String requestJson) async {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    if (request['method'] == 'convertShareLinksToXrayJson') {
      return jsonEncode({
        'success': true,
        'data': {
          'outbounds': [
            {
              'protocol': 'vmess',
              'sendThrough': '家庭节点',
              'settings': {'address': 'private.example'},
            },
          ],
        },
        'error': '',
      });
    }
    return jsonEncode({'success': true, 'data': {}, 'error': ''});
  }
}
