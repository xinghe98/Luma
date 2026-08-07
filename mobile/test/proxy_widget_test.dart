import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/app/controllers/session_controller.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/proxy/proxy_profile_store.dart';
import 'package:luma/data/proxy/proxy_route.dart';
import 'package:luma/data/proxy/vmess_proxy_controller.dart';
import 'package:luma/data/proxy/vmess_proxy_profile.dart';
import 'package:luma/data/proxy/xray_bridge.dart';
import 'package:luma/data/services/connection_service.dart';
import 'package:luma/features/connection/connection_controller.dart';
import 'package:luma/features/connection/connection_page.dart';
import 'package:luma/features/connection/widgets/connection_form.dart';
import 'package:luma/features/connection/widgets/vmess_proxy_control.dart';

void main() {
  testWidgets(
    'app bar opens dialog; link field imports without rendering secrets',
    (tester) async {
      final controller = _controller(_WidgetNative());
      await controller.load();
      await _pumpAction(tester, controller);

      expect(find.text('代理'), findsOneWidget);
      await tester.tap(find.text('代理'));
      await tester.pumpAndSettle();

      expect(find.text('连接代理'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'vmess://sensitive-uuid');
      await tester.tap(find.widgetWithText(FilledButton, '连接'));
      await tester.pumpAndSettle();

      // 启动成功后弹层关闭，AppBar 显示已开。
      expect(find.text('连接代理'), findsNothing);
      expect(find.text('代理已开'), findsOneWidget);
      expect(find.textContaining('sensitive-uuid'), findsNothing);
      await controller.disposeProxy();
    },
  );

  testWidgets('dialog start/stop labels track busy and active phases', (
    tester,
  ) async {
    final native = _WidgetNative();
    final controller = _controller(native);
    await controller.load();
    await controller.importFromClipboard('vmess://fixture');
    await _pumpAction(tester, controller);

    await tester.tap(find.text('代理'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已保存 · 家庭节点'), findsOneWidget);

    native.runGate = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, '启动代理'));
    await tester.pump();
    expect(find.text('连接中…'), findsOneWidget);

    native.runGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('连接代理'), findsNothing);
    expect(find.text('代理已开'), findsOneWidget);

    await tester.tap(find.text('代理已开'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已连接 · 家庭节点'), findsOneWidget);

    native.stopGate = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, '关闭代理'));
    await tester.pump();
    expect(find.text('关闭中…'), findsOneWidget);
    native.stopGate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('已保存 · 家庭节点'), findsOneWidget);
    expect(find.text('代理'), findsOneWidget);
    await controller.disposeProxy();
  });

  testWidgets('failure remains recoverable and redacts native details', (
    tester,
  ) async {
    final controller = _controller(_WidgetNative(failRun: true));
    await controller.load();
    await controller.importFromClipboard('vmess://fixture');
    await controller.start();
    await _pumpAction(tester, controller);

    await tester.tap(find.text('代理'));
    await tester.pumpAndSettle();

    expect(find.text(VmessProxyController.failureMessage), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('native secret'), findsNothing);
    expect(find.textContaining('sensitive'), findsNothing);
    await controller.disposeProxy();
  });

  testWidgets('connection form switches direct and VMess security copy', (
    tester,
  ) async {
    final connection = ConnectionController(
      connectionService: _UnavailableConnectionService(),
      sessionController: SessionController(),
      mediaController: MediaController(MockMediaRepository()),
      successDelay: Duration.zero,
    );
    final textControllers = List.generate(4, (_) => TextEditingController());
    addTearDown(() {
      connection.dispose();
      for (final controller in textControllers) {
        controller.dispose();
      }
    });

    await tester.pumpWidget(
      _formApp(connection, textControllers, proxied: false),
    );
    expect(find.textContaining('可信局域网内传输'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).autofocus,
      isFalse,
    );

    await tester.pumpWidget(
      _formApp(connection, textControllers, proxied: true),
    );
    expect(find.textContaining('通过 VMess 通道发送'), findsOneWidget);
  });

  testWidgets('connection page disables proxy action while login is pending', (
    tester,
  ) async {
    final service = _PendingConnectionService();
    final proxy = _controller(_WidgetNative());
    await proxy.load();
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: service,
      proxyController: proxy,
    );
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          dependencies: dependencies,
          child: const ConnectionPage(),
        ),
      ),
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '代理'))
          .onPressed,
      isNotNull,
    );

    await tester.enterText(find.byType(TextField).first, 'private.example');
    await tester.tap(find.widgetWithText(FilledButton, '立即连接'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '代理'))
          .onPressed,
      isNull,
    );

    service.loginCompleter.complete(ConnectionResult.unreachable);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '代理'))
          .onPressed,
      isNotNull,
    );
  });
}

Future<void> _pumpAction(WidgetTester tester, VmessProxyController controller) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            VmessProxyAppBarAction(
              controller: controller,
              enabled: true,
              onStart: () async {
                await controller.start();
                return controller.isActive;
              },
              onStop: controller.stop,
              onImport: controller.importFromClipboard,
              onDelete: controller.deleteProfile,
            ),
          ],
        ),
        body: const SizedBox.shrink(),
      ),
    ),
  );
}

Widget _formApp(
  ConnectionController connection,
  List<TextEditingController> controllers, {
  required bool proxied,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ConnectionForm(
        controller: connection,
        hostController: controllers[0],
        portController: controllers[1],
        usernameController: controllers[2],
        passwordController: controllers[3],
        proxied: proxied,
        enabled: true,
        onConnect: () {},
      ),
    ),
  );
}

VmessProxyController _controller(_WidgetNative native) {
  final bridge = XrayBridge(rawInvoker: native.invoke);
  return VmessProxyController(
    store: _MemoryProxyProfileStore(),
    parser: VmessProfileParser(bridge),
    bridge: bridge,
    route: ProxyRoute(),
    portProbe: (_) async => true,
  );
}

final class _WidgetNative {
  _WidgetNative({this.failRun = false});

  final bool failRun;
  Completer<void>? runGate;
  Completer<void>? stopGate;

  Future<String> invoke(String requestJson) async {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    final method = request['method'];
    if (method == 'convertShareLinksToXrayJson') {
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
    if (method == 'getFreePorts') {
      return jsonEncode({
        'success': true,
        'data': {
          'ports': [32123],
        },
        'error': '',
      });
    }
    if (method == 'getXrayState') {
      return jsonEncode({
        'success': true,
        'data': {'running': true},
        'error': '',
      });
    }
    if (method == 'runXrayFromJson') {
      if (runGate != null) await runGate!.future;
      if (failRun) {
        return jsonEncode({
          'success': false,
          'data': null,
          'error': 'native secret',
        });
      }
      return jsonEncode({'success': true, 'data': {}, 'error': ''});
    }
    if (method == 'stopXray') {
      if (stopGate != null) await stopGate!.future;
      return jsonEncode({'success': true, 'data': {}, 'error': ''});
    }
    return jsonEncode({'success': true, 'data': {}, 'error': ''});
  }
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

final class _UnavailableConnectionService implements ConnectionService {
  @override
  ServerProfile? get connectedProfile => null;

  @override
  Future<ConnectionResult> login(
    String address,
    LoginCredentials credentials,
  ) async => ConnectionResult.unreachable;

  @override
  Future<ConnectionResult> restore(String address, String sessionToken) async =>
      ConnectionResult.unauthorized;

  @override
  Future<void> disconnect() async {}
}

final class _PendingConnectionService implements ConnectionService {
  final Completer<ConnectionResult> loginCompleter =
      Completer<ConnectionResult>();

  @override
  ServerProfile? get connectedProfile => null;

  @override
  Future<ConnectionResult> login(
    String address,
    LoginCredentials credentials,
  ) async => loginCompleter.future;

  @override
  Future<ConnectionResult> restore(String address, String sessionToken) async =>
      ConnectionResult.unauthorized;

  @override
  Future<void> disconnect() async {}
}
