import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luma/data/proxy/proxy_profile_store.dart';
import 'package:luma/data/proxy/proxy_route.dart';
import 'package:luma/data/proxy/vmess_proxy_controller.dart';
import 'package:luma/data/proxy/vmess_proxy_profile.dart';
import 'package:luma/data/proxy/xray_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native libXray starts manually and profile reload stays inactive',
    (tester) async {
      final bridge = XrayBridge();
      final version = await bridge.invoke('xrayVersion');
      expect(version, {'version': '26.7.28'});

      final store = _MemoryProxyProfileStore();
      final route = ProxyRoute();
      final controller = VmessProxyController(
        store: store,
        parser: VmessProfileParser(bridge),
        bridge: bridge,
        route: route,
      );
      await controller.load();
      expect(controller.phase, VmessProxyPhase.inactive);

      await controller.importFromClipboard(_fixtureLink());
      expect(controller.profile?.displayName, '烟测节点');
      await controller.start();
      expect(controller.phase, VmessProxyPhase.active);
      expect(controller.endpoint?.port, greaterThan(0));
      expect(
        route.findProxy(Uri.parse('http://private.example')),
        startsWith('PROXY '),
      );
      expect(route.findProxy(Uri.parse('http://127.0.0.1/media')), 'DIRECT');

      await controller.stop();
      expect(controller.phase, VmessProxyPhase.inactive);
      expect(route.findProxy(Uri.parse('http://private.example')), 'DIRECT');

      final reloaded = VmessProxyController(
        store: store,
        parser: VmessProfileParser(bridge),
        bridge: bridge,
        route: ProxyRoute(),
      );
      await reloaded.load();
      expect(reloaded.profile?.id, controller.profile?.id);
      expect(reloaded.phase, VmessProxyPhase.inactive);

      await reloaded.disposeProxy();
      await controller.disposeProxy();
    },
  );
}

String _fixtureLink() {
  final payload = jsonEncode({
    'v': '2',
    'ps': '烟测节点',
    'add': 'example.com',
    'port': '443',
    'id': '11111111-1111-1111-1111-111111111111',
    'aid': '0',
    'scy': 'auto',
    'net': 'tcp',
    'type': 'none',
    'host': '',
    'path': '',
    'tls': 'tls',
    'sni': 'example.com',
  });
  return 'vmess://${base64Encode(utf8.encode(payload))}';
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
