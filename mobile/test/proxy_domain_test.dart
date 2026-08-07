import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/proxy/proxy_profile_store.dart';
import 'package:luma/data/proxy/proxy_route.dart';
import 'package:luma/data/proxy/vmess_proxy_controller.dart';
import 'package:luma/data/proxy/vmess_proxy_profile.dart';
import 'package:luma/data/proxy/xray_bridge.dart';
import 'package:luma/data/services/connection_service.dart';
import 'package:luma/data/storage/credential_store.dart';
import 'package:luma/data/storage/secure_credential_store.dart';

import 'package:luma/features/connection/connection_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('XrayBridge', () {
    test(
      'strictly decodes API v1 envelope and rejects unsupported methods',
      () async {
        final bridge = XrayBridge(
          rawInvoker: (_) async =>
              '{"success":true,"data":{"version":"26.7.28"},"error":""}',
        );
        expect(await bridge.invoke('xrayVersion'), {'version': '26.7.28'});
        await expectLater(
          bridge.invoke('ping', {'secret': 'must-not-leak'}),
          throwsA(
            isA<XrayBridgeException>().having(
              (error) => error.toString(),
              'sanitized message',
              isNot(contains('secret')),
            ),
          ),
        );
      },
    );

    test('maps convert logical failures without leaking native errors', () async {
      final bridge = XrayBridge(
        rawInvoker: (_) async =>
            '{"success":false,"data":null,"error":"uuid secret no valid outbound"}',
      );
      await expectLater(
        bridge.invoke('convertShareLinksToXrayJson', {
          'text': 'vmess://fixture',
        }),
        throwsA(
          isA<XrayBridgeException>().having(
            (error) => error.message,
            'message',
            XrayBridgeException.invalidShareLinkMessage,
          ),
        ),
      );
      await expectLater(
        bridge.invoke('convertShareLinksToXrayJson', {
          'text': 'vmess://fixture',
        }),
        throwsA(
          isA<XrayBridgeException>().having(
            (error) => error.toString(),
            'sanitized message',
            isNot(contains('secret')),
          ),
        ),
      );
    });

    test('native and malformed failures expose only a fixed message', () async {
      for (final response in [
        '{"success":false,"data":null,"error":"uuid secret"}',
        '{"success":true}',
        'not-json',
      ]) {
        final bridge = XrayBridge(rawInvoker: (_) async => response);
        await expectLater(
          bridge.invoke('xrayVersion'),
          throwsA(
            isA<XrayBridgeException>().having(
              (error) => error.message,
              'message',
              XrayBridgeException.serviceUnavailableMessage,
            ),
          ),
        );
      }

      final transportBroken = XrayBridge(
        rawInvoker: (_) async => throw Exception('dll missing secret'),
      );
      await expectLater(
        transportBroken.invoke('convertShareLinksToXrayJson', {
          'text': 'vmess://fixture',
        }),
        throwsA(
          isA<XrayBridgeException>().having(
            (error) => error.message,
            'message',
            XrayBridgeException.serviceUnavailableMessage,
          ),
        ),
      );
    });

    test('serializes native calls', () async {
      var active = 0;
      var maximumActive = 0;
      final bridge = XrayBridge(
        rawInvoker: (_) async {
          active++;
          maximumActive = active > maximumActive ? active : maximumActive;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          return '{"success":true,"data":{},"error":""}';
        },
      );
      await Future.wait([
        bridge.invoke('getXrayState'),
        bridge.invoke('getXrayState'),
        bridge.invoke('getXrayState'),
      ]);
      expect(maximumActive, 1);
    });
  });

  group('VMess profile parsing', () {
    test('link gate accepts only one exact lower-case vmess line', () {
      expect(
        VmessProfileParser.normalizeLink(' vmess://fixture '),
        'vmess://fixture',
      );
      for (final value in [
        '',
        'VMESS://fixture',
        'vless://fixture',
        'vmess://one\nvmess://two',
        'vmess://${'a' * (32 * 1024)}',
      ]) {
        expect(
          () => VmessProfileParser.normalizeLink(value),
          throwsA(isA<XrayBridgeException>()),
        );
      }
    });

    test('rewrites base64 cipher:uuid@host:port into plain vmess URL', () {
      const legacy =
          'vmess://YXV0bzoyNzdjMjcwMS1hZWNmLTQ4ZWUtYjc1NS1iZGQ1NjQ2YmQzYWJAbGlhbmR5dWFuLnRvcDo5ODk5';
      expect(
        VmessProfileParser.normalizeLink(legacy),
        'vmess://277c2701-aecf-48ee-b755-bdd5646bd3ab@liandyuan.top:9899?encryption=auto',
      );
    });

    test('strips clipboard junk before legacy rewrite', () {
      const legacy =
          'vmess://YXV0bzoyNzdjMjcwMS1hZWNmLTQ4ZWUtYjc1NS1iZGQ1NjQ2YmQzYWJAbGlhbmR5dWFuLnRvcDo5ODk5';
      const expected =
          'vmess://277c2701-aecf-48ee-b755-bdd5646bd3ab@liandyuan.top:9899?encryption=auto';
      expect(VmessProfileParser.normalizeLink('\ufeff$legacy，'), expected);
      expect(VmessProfileParser.normalizeLink('$legacy。'), expected);
    });
    test('leaves standard JSON QR base64 vmess links unchanged', () {
      final payload = base64Encode(
        utf8.encode(
          jsonEncode({
            'v': '2',
            'ps': 'node',
            'add': 'example.com',
            'port': '443',
            'id': '11111111-1111-1111-1111-111111111111',
            'aid': '0',
            'scy': 'auto',
            'net': 'tcp',
          }),
        ),
      );
      final link = 'vmess://$payload';
      expect(VmessProfileParser.normalizeLink(link), link);
    });

    test(
      'keeps one VMess outbound, sanitizes its name, and drops sendThrough',
      () async {
        final parser = VmessProfileParser(
          _bridgeWithConverter([
            {
              'protocol': 'vmess',
              'sendThrough': '  家庭\n节点\u0000  ',
              'settings': {'address': 'private.example', 'id': 'uuid'},
            },
          ]),
        );
        final parsed = await parser.parseOutbound('vmess://fixture');
        expect(parsed.displayName, '家庭 节点');
        expect(parsed.outbound['protocol'], 'vmess');
        expect(parsed.outbound, isNot(contains('sendThrough')));
      },
    );

    test('rejects multiple and non-VMess outbounds', () async {
      for (final outbounds in [
        <Object?>[],
        [
          {'protocol': 'vmess', 'settings': {}},
          {'protocol': 'vmess', 'settings': {}},
        ],
        [
          {'protocol': 'vless', 'settings': {}},
        ],
      ]) {
        final parser = VmessProfileParser(_bridgeWithConverter(outbounds));
        await expectLater(
          parser.parseOutbound('vmess://fixture'),
          throwsA(
            isA<XrayBridgeException>().having(
              (error) => error.message,
              'message',
              XrayBridgeException.invalidShareLinkMessage,
            ),
          ),
        );
      }
    });
  });

  test('controller builds minimal config and cuts route before stop', () async {
    final native = _FakeNative();
    final bridge = XrayBridge(rawInvoker: native.invoke);
    final store = _MemoryProxyProfileStore();
    final route = ProxyRoute();
    final controller = VmessProxyController(
      store: store,
      parser: VmessProfileParser(bridge),
      bridge: bridge,
      route: route,
      portProbe: (_) async => true,
    );

    await controller.load();
    await controller.importFromClipboard('vmess://fixture');
    final profileId = controller.profile!.id;
    await controller.start();

    expect(controller.phase, VmessProxyPhase.active);
    expect(controller.activeProfileId, profileId);
    expect(
      route.findProxy(Uri.parse('http://private.example')),
      'PROXY 127.0.0.1:32123',
    );
    expect(route.findProxy(Uri.parse('https://127.0.0.1/media')), 'DIRECT');
    final config = native.runConfig!;
    expect(
      config.keys,
      unorderedEquals(['log', 'inbounds', 'outbounds', 'routing']),
    );
    final inbound = (config['inbounds'] as List).single as Map;
    expect(inbound['listen'], '127.0.0.1');
    expect(inbound['protocol'], 'http');
    final outbound = (config['outbounds'] as List).single as Map;
    expect(outbound['protocol'], 'vmess');
    expect(outbound['tag'], 'luma-vmess-out');
    expect(outbound, isNot(contains('sendThrough')));

    final stop = controller.stop();
    expect(route.findProxy(Uri.parse('http://private.example')), 'DIRECT');
    await stop;
    expect(controller.phase, VmessProxyPhase.inactive);
    await controller.disposeProxy();
  });

  test(
    'failed manual restore remains retryable and preserves active proxy',
    () async {
      final native = _FakeNative();
      final bridge = XrayBridge(rawInvoker: native.invoke);
      final profile = const VmessProxyProfile(
        id: 'profile-a',
        displayName: '家庭节点',
        shareLink: 'vmess://fixture',
      );
      final profileStore = _MemoryProxyProfileStore()..value = profile;
      final route = ProxyRoute();
      final proxy = VmessProxyController(
        store: profileStore,
        parser: VmessProfileParser(bridge),
        bridge: bridge,
        route: route,
        portProbe: (_) async => true,
      );
      await proxy.load();
      final credentials = _MemoryCredentialStore(
        const StoredCredentials(
          origin: 'http://private.example:8080',
          sessionToken: 'session-token',
          proxyProfileId: 'profile-a',
        ),
      );
      final connection = _RestoringConnectionService(
        restoreResults: [
          ConnectionResult.unreachable,
          ConnectionResult.success,
        ],
      );
      final dependencies = AppDependencies(
        mediaRepository: MockMediaRepository(),
        connectionService: connection,
        credentialStore: credentials,
        proxyController: proxy,
        proxyRoute: route,
      );

      expect(await dependencies.restoreSession(), isFalse);
      expect(connection.restoreCalls, 0);
      expect(proxy.phase, VmessProxyPhase.inactive);

      expect(await dependencies.startProxy(), isFalse);
      expect(connection.restoreCalls, 1);
      expect(dependencies.restoring.value, isFalse);
      expect(dependencies.session.server, isNull);
      expect(proxy.isActive, isTrue);

      await dependencies.stopProxy();
      expect(proxy.phase, VmessProxyPhase.inactive);
      expect(await dependencies.startProxy(), isTrue);
      expect(connection.restoreCalls, 2);
      expect(dependencies.session.server, isNotNull);
      expect(proxy.isActive, isTrue);

      await dependencies.stopProxy();
      expect(
        proxy.isActive,
        isTrue,
        reason: 'active server sessions lock proxy changes',
      );
      await dependencies.disconnect();
      expect(connection.disconnectCalls, 1);
      expect(proxy.isActive, isTrue);

      await dependencies.stopProxy();
      expect(proxy.phase, VmessProxyPhase.inactive);
      expect(route.findProxy(Uri.parse('http://private.example')), 'DIRECT');
      dependencies.dispose();
    },
  );

  test(
    'connection and restore windows freeze every proxy configuration action',
    () async {
      final native = _FakeNative();
      final bridge = XrayBridge(rawInvoker: native.invoke);
      final store = _MemoryProxyProfileStore();
      final route = ProxyRoute();
      final proxy = VmessProxyController(
        store: store,
        parser: VmessProfileParser(bridge),
        bridge: bridge,
        route: route,
        portProbe: (_) async => true,
      );
      await proxy.load();
      await proxy.importFromClipboard('vmess://fixture');
      final profile = proxy.profile;
      final connection = _PendingConnectionService();
      final dependencies = AppDependencies(
        mediaRepository: MockMediaRepository(),
        connectionService: connection,
        proxyController: proxy,
        proxyRoute: route,
      );

      final pendingLogin = dependencies.connection.connect(
        'http://private.example:8080',
        const LoginCredentials(username: 'user', password: 'password'),
      );
      expect(dependencies.canConfigureProxy, isFalse);
      final nativeCalls = native.calls.length;
      final writes = store.writeCalls;
      final clears = store.clearCalls;
      expect(await dependencies.startProxy(), isFalse);
      await dependencies.stopProxy();
      await dependencies.importProxyProfile('vmess://replacement');
      await dependencies.deleteProxyProfile();
      expect(native.calls.length, nativeCalls);
      expect(store.writeCalls, writes);
      expect(store.clearCalls, clears);
      expect(proxy.profile, same(profile));
      expect(route.isActive, isFalse);

      connection.loginCompleter.complete(ConnectionResult.unreachable);
      await pendingLogin;
      expect(dependencies.canConfigureProxy, isTrue);

      dependencies.restoring.value = true;
      expect(await dependencies.startProxy(), isFalse);
      await dependencies.stopProxy();
      await dependencies.importProxyProfile('vmess://replacement');
      await dependencies.deleteProxyProfile();
      expect(native.calls.length, nativeCalls);
      expect(store.writeCalls, writes);
      expect(store.clearCalls, clears);
      dependencies.restoring.value = false;

      connection.resetLogin();
      final successfulLogin = dependencies.connection.connect(
        'http://private.example:8080',
        const LoginCredentials(username: 'user', password: 'password'),
      );
      connection.loginCompleter.complete(ConnectionResult.success);
      await Future<void>.delayed(Duration.zero);
      expect(dependencies.connection.phase, ConnectionPhase.success);
      expect(dependencies.canConfigureProxy, isFalse);
      expect(await dependencies.startProxy(), isFalse);
      await successfulLogin;
      expect(dependencies.session.server, isNotNull);
      expect(dependencies.canConfigureProxy, isFalse);

      dependencies.dispose();
    },
  );

  test('stop during start cancels readiness polling and closes core', () async {
    final native = _LifecycleNative()..runGate = Completer<void>();
    final bridge = XrayBridge(rawInvoker: native.invoke);
    final route = ProxyRoute();
    final controller = VmessProxyController(
      store: _MemoryProxyProfileStore(),
      parser: VmessProfileParser(bridge),
      bridge: bridge,
      route: route,
      portProbe: (_) async => true,
    );
    await controller.load();
    await controller.importFromClipboard('vmess://fixture');

    final start = controller.start();
    await native.runEntered.future;
    expect(controller.phase, VmessProxyPhase.starting);
    final stop = controller.stop();
    expect(controller.phase, VmessProxyPhase.stopping);
    expect(route.isActive, isFalse);

    native.runGate!.complete();
    await Future.wait([start, stop]);
    expect(
      native.calls.where(
        (method) => method == 'runXrayFromJson' || method == 'stopXray',
      ),
      ['runXrayFromJson', 'stopXray'],
    );
    expect(native.getStateCalls, 0);
    expect(controller.phase, VmessProxyPhase.inactive);
    expect(route.isActive, isFalse);
    await controller.disposeProxy();
  });

  test(
    'explicit stop failure leaves DIRECT route and actionable state',
    () async {
      final native = _LifecycleNative(stopFailure: true);
      final bridge = XrayBridge(rawInvoker: native.invoke);
      final route = ProxyRoute();
      final controller = VmessProxyController(
        store: _MemoryProxyProfileStore(),
        parser: VmessProfileParser(bridge),
        bridge: bridge,
        route: route,
        portProbe: (_) async => true,
      );
      await controller.load();
      await controller.importFromClipboard('vmess://fixture');
      await controller.start();
      expect(controller.phase, VmessProxyPhase.active);

      await controller.stop();
      expect(route.isActive, isFalse);
      expect(controller.phase, VmessProxyPhase.failure);
      expect(controller.message, VmessProxyController.stopFailureMessage);
      await controller.disposeProxy();
    },
  );

  test('disposed controller rejects every public operation', () async {
    final native = _LifecycleNative();
    final bridge = XrayBridge(rawInvoker: native.invoke);
    final route = ProxyRoute();
    final store = _MemoryProxyProfileStore();
    final controller = VmessProxyController(
      store: store,
      parser: VmessProfileParser(bridge),
      bridge: bridge,
      route: route,
      portProbe: (_) async => true,
    );
    await controller.load();
    await controller.importFromClipboard('vmess://fixture');
    await controller.disposeProxy();
    final calls = native.calls.length;
    final reads = store.readCalls;
    final writes = store.writeCalls;
    final clears = store.clearCalls;

    await controller.load();
    await controller.importFromClipboard('vmess://replacement');
    await controller.deleteProfile();
    await controller.start();
    await controller.stop();

    expect(native.calls.length, calls);
    expect(store.readCalls, reads);
    expect(store.writeCalls, writes);
    expect(store.clearCalls, clears);
    expect(route.isActive, isFalse);
  });

  test('load and start reject active or transitional reentry', () async {
    final native = _LifecycleNative()..runGate = Completer<void>();
    final bridge = XrayBridge(rawInvoker: native.invoke);
    final route = ProxyRoute();
    final store = _MemoryProxyProfileStore();
    final controller = VmessProxyController(
      store: store,
      parser: VmessProfileParser(bridge),
      bridge: bridge,
      route: route,
      portProbe: (_) async => true,
    );

    await controller.start();
    expect(controller.phase, VmessProxyPhase.loading);
    expect(native.calls, isEmpty);

    await controller.load();
    await controller.importFromClipboard('vmess://fixture');
    final start = controller.start();
    await native.runEntered.future;
    final startingCalls = native.calls.length;
    await controller.start();
    expect(controller.phase, VmessProxyPhase.starting);
    expect(native.calls.length, startingCalls);

    native.runGate!.complete();
    await start;
    expect(controller.phase, VmessProxyPhase.active);
    final profile = controller.profile;
    final endpoint = controller.endpoint;
    final activeCalls = native.calls.length;
    final reads = store.readCalls;
    await controller.load();
    expect(controller.phase, VmessProxyPhase.active);
    expect(controller.profile, same(profile));
    expect(controller.endpoint, same(endpoint));
    expect(native.calls.length, activeCalls);
    expect(store.readCalls, reads);

    native.stopGate = Completer<void>();
    final stop = controller.stop();
    await native.stopEntered.future;
    final stoppingCalls = native.calls.length;
    await controller.start();
    expect(controller.phase, VmessProxyPhase.stopping);
    expect(native.calls.length, stoppingCalls);
    native.stopGate!.complete();
    await stop;
    expect(controller.phase, VmessProxyPhase.inactive);
    await controller.disposeProxy();
  });

  test(
    'secure credentials read v2 and atomically write v3 profile ID',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'luma.api.credentials.v2': jsonEncode({
          'origin': 'http://server.local:8080',
          'session_token': 'old-token',
        }),
      });
      const storage = FlutterSecureStorage();
      const store = SecureCredentialStore(storage);
      final old = await store.read();
      expect(old?.proxyProfileId, isNull);

      await store.write(
        const StoredCredentials(
          origin: 'http://server.local:8080',
          sessionToken: 'new-token',
          proxyProfileId: 'profile-a',
        ),
      );
      final encoded = await storage.read(key: 'luma.api.credentials.v3');
      expect(jsonDecode(encoded!)['proxy_profile_id'], 'profile-a');
    },
  );
}

XrayBridge _bridgeWithConverter(List<Object?> outbounds) => XrayBridge(
  rawInvoker: (_) async => jsonEncode({
    'success': true,
    'data': {'outbounds': outbounds},
    'error': '',
  }),
);

final class _FakeNative {
  bool running = false;
  final List<String> calls = [];
  Map<String, dynamic>? runConfig;

  Future<String> invoke(String requestJson) async {
    final request = jsonDecode(requestJson) as Map<String, dynamic>;
    final method = request['method'];
    calls.add(method as String);
    Object? data;
    switch (method) {
      case 'convertShareLinksToXrayJson':
        data = {
          'outbounds': [
            {
              'protocol': 'vmess',
              'sendThrough': '家庭节点',
              'settings': {
                'address': 'private.example',
                'id': '11111111-1111-1111-1111-111111111111',
              },
            },
          ],
        };
      case 'getFreePorts':
        data = {
          'ports': [32123],
        };
      case 'runXrayFromJson':
        final payload = request['payload'] as Map<String, dynamic>;
        runConfig = jsonDecode(payload['configJSON'] as String);
        running = true;
        data = <String, Object?>{};
      case 'getXrayState':
        data = {'running': running};
      case 'stopXray':
        running = false;
        data = <String, Object?>{};
      default:
        data = <String, Object?>{};
    }
    return jsonEncode({'success': true, 'data': data, 'error': ''});
  }
}

final class _LifecycleNative {
  _LifecycleNative({this.stopFailure = false});

  final bool stopFailure;
  final List<String> calls = [];
  final Completer<void> runEntered = Completer<void>();
  final Completer<void> stopEntered = Completer<void>();
  Completer<void>? runGate;
  Completer<void>? stopGate;
  bool running = false;
  int getStateCalls = 0;

  Future<String> invoke(String requestJson) async {
    final request = jsonDecode(requestJson) as Map<String, dynamic>;
    final method = request['method'] as String;
    calls.add(method);
    Object? data;
    switch (method) {
      case 'convertShareLinksToXrayJson':
        data = {
          'outbounds': [
            {
              'protocol': 'vmess',
              'sendThrough': '家庭节点',
              'settings': {'address': 'private.example'},
            },
          ],
        };
      case 'getFreePorts':
        data = {
          'ports': [32123],
        };
      case 'runXrayFromJson':
        if (!runEntered.isCompleted) runEntered.complete();
        await runGate?.future;
        running = true;
        data = <String, Object?>{};
      case 'getXrayState':
        getStateCalls++;
        data = {'running': running};
      case 'stopXray':
        if (!stopEntered.isCompleted) stopEntered.complete();
        await stopGate?.future;
        if (stopFailure) {
          return jsonEncode({
            'success': false,
            'data': null,
            'error': 'native stop detail',
          });
        }
        running = false;
        data = <String, Object?>{};
      default:
        data = <String, Object?>{};
    }
    return jsonEncode({'success': true, 'data': data, 'error': ''});
  }
}

final class _MemoryProxyProfileStore implements ProxyProfileStore {
  VmessProxyProfile? value;
  int readCalls = 0;
  int writeCalls = 0;
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls++;
    value = null;
  }

  @override
  Future<VmessProxyProfile?> read() async {
    readCalls++;
    return value;
  }

  @override
  Future<void> write(VmessProxyProfile profile) async {
    writeCalls++;
    value = profile;
  }
}

final class _MemoryCredentialStore implements CredentialStore {
  _MemoryCredentialStore(this.value);

  StoredCredentials? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredCredentials?> read() async => value;

  @override
  Future<void> write(StoredCredentials credentials) async =>
      value = credentials;
}

final class _RestoringConnectionService implements ConnectionService {
  _RestoringConnectionService({
    this.restoreResults = const [ConnectionResult.success],
  });

  final List<ConnectionResult> restoreResults;
  int restoreCalls = 0;
  int disconnectCalls = 0;

  @override
  ServerProfile? connectedProfile;

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    connectedProfile = null;
  }

  @override
  Future<ConnectionResult> login(
    String address,
    LoginCredentials credentials,
  ) async => ConnectionResult.unreachable;

  @override
  Future<ConnectionResult> restore(String address, String sessionToken) async {
    final result = restoreResults[restoreCalls++];
    if (result == ConnectionResult.success) {
      connectedProfile = ServerProfile(
        name: 'Private server',
        address: address,
        token: sessionToken,
        hostName: 'private.example',
      );
    }
    return result;
  }
}

final class _PendingConnectionService implements ConnectionService {
  Completer<ConnectionResult> loginCompleter = Completer<ConnectionResult>();

  @override
  ServerProfile? connectedProfile;

  void resetLogin() {
    loginCompleter = Completer<ConnectionResult>();
  }

  @override
  Future<ConnectionResult> login(
    String address,
    LoginCredentials credentials,
  ) async {
    final result = await loginCompleter.future;
    if (result == ConnectionResult.success) {
      connectedProfile = ServerProfile(
        name: 'Private server',
        address: address,
        token: 'session-token',
        hostName: 'private.example',
      );
    }
    return result;
  }

  @override
  Future<ConnectionResult> restore(String address, String sessionToken) async =>
      ConnectionResult.unauthorized;

  @override
  Future<void> disconnect() async {
    connectedProfile = null;
  }
}
