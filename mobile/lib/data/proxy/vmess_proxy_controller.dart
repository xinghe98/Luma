import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'proxy_profile_store.dart';
import 'proxy_route.dart';
import 'vmess_proxy_profile.dart';
import 'xray_bridge.dart';

enum VmessProxyPhase { loading, inactive, starting, active, stopping, failure }

typedef ProxyPortProbe = Future<bool> Function(int port);

final class VmessProxyController extends ChangeNotifier {
  VmessProxyController({
    required ProxyProfileStore store,
    required VmessProfileParser parser,
    required XrayBridge bridge,
    required ProxyRoute route,
    ProxyPortProbe? portProbe,
  }) : _store = store,
       _parser = parser,
       _bridge = bridge,
       _route = route,
       _portProbe = portProbe ?? _defaultPortProbe;

  static const failureMessage = 'VMess 代理启动失败，请检查配置后重试';
  static const stopFailureMessage = 'VMess 代理关闭失败，请重启应用后重试';

  final ProxyProfileStore _store;
  final VmessProfileParser _parser;
  final XrayBridge _bridge;
  final ProxyRoute _route;
  final ProxyPortProbe _portProbe;

  VmessProxyPhase _phase = VmessProxyPhase.loading;
  VmessProxyProfile? _profile;
  String? _message;
  int _operation = 0;
  bool _disposed = false;

  VmessProxyPhase get phase => _phase;
  VmessProxyProfile? get profile => _profile;
  String? get message => _message;
  bool get isActive => _phase == VmessProxyPhase.active && _route.isActive;
  String? get activeProfileId => _route.endpoint?.profileId;
  ProxyEndpoint? get endpoint => _route.endpoint;
  bool get canEditProfile =>
      _phase == VmessProxyPhase.inactive || _phase == VmessProxyPhase.failure;

  /// 只读取安全存储。进程启动后始终保持未启动。
  Future<void> load() async {
    if (_disposed ||
        _route.isActive ||
        _phase == VmessProxyPhase.starting ||
        _phase == VmessProxyPhase.stopping) {
      return;
    }
    final operation = ++_operation;
    _setState(VmessProxyPhase.loading);
    try {
      final profile = await _store.read();
      if (!_isCurrent(operation)) return;
      _profile = profile;
      _setState(VmessProxyPhase.inactive);
    } catch (_) {
      if (!_isCurrent(operation)) return;
      _profile = null;
      _setState(VmessProxyPhase.failure, '读取代理配置失败，请重新导入');
    }
  }

  Future<void> importFromClipboard(String clipboardText) async {
    if (_disposed) return;
    if (!canEditProfile) return;
    final operation = ++_operation;
    _setState(VmessProxyPhase.loading);
    try {
      final profile = await _parser.createProfile(clipboardText);
      await _store.write(profile);
      if (!_isCurrent(operation)) return;
      _profile = profile;
      _setState(VmessProxyPhase.inactive);
    } on XrayBridgeException catch (error) {
      if (!_isCurrent(operation)) return;
      _setState(VmessProxyPhase.failure, error.message);
    } catch (_) {
      if (!_isCurrent(operation)) return;
      _setState(VmessProxyPhase.failure, 'VMess 配置保存失败，请重试');
    }
  }

  Future<void> deleteProfile() async {
    if (_disposed) return;
    if (!canEditProfile) return;
    final operation = ++_operation;
    _setState(VmessProxyPhase.loading);
    try {
      await _store.clear();
      if (!_isCurrent(operation)) return;
      _profile = null;
      _setState(VmessProxyPhase.inactive);
    } catch (_) {
      if (!_isCurrent(operation)) return;
      _setState(VmessProxyPhase.failure, 'VMess 配置删除失败，请重试');
    }
  }

  Future<void> start() async {
    if (_disposed ||
        (_phase != VmessProxyPhase.inactive &&
            _phase != VmessProxyPhase.failure)) {
      return;
    }
    final profile = _profile;
    if (profile == null) {
      _setState(VmessProxyPhase.failure, '请先导入 VMess 分享链接');
      return;
    }

    final operation = ++_operation;
    _route.deactivate();
    _setState(VmessProxyPhase.starting);
    try {
      final parsed = await _parser.parseOutbound(profile.shareLink);
      final port = await _getFreePort();
      final username = _randomSecret(12);
      final password = _randomSecret(32);
      final config = _buildConfig(
        port: port,
        username: username,
        password: password,
        outbound: parsed.outbound,
      );
      await _bridge.invoke('runXrayFromJson', {
        'configJSON': jsonEncode(config),
      });
      if (!await _waitUntilReady(port, operation) || !_isCurrent(operation)) {
        throw const XrayBridgeException();
      }
      _route.activate(
        ProxyEndpoint(
          profileId: profile.id,
          host: '127.0.0.1',
          port: port,
          username: username,
          password: password,
        ),
      );
      _setState(VmessProxyPhase.active);
    } catch (_) {
      if (!_isCurrent(operation)) return;
      _route.deactivate();
      await _bestEffortStop();
      if (!_isCurrent(operation)) return;
      _setState(VmessProxyPhase.failure, failureMessage);
    }
  }

  Future<void> stop() async {
    if (_disposed || _phase == VmessProxyPhase.stopping) return;
    if (!_route.isActive &&
        (_phase == VmessProxyPhase.inactive ||
            _phase == VmessProxyPhase.loading)) {
      return;
    }
    final operation = ++_operation;
    // 先切回 DIRECT，阻止新请求进入即将关闭的入口。
    _route.deactivate();
    _setState(VmessProxyPhase.stopping);
    try {
      await _bridge.invoke('stopXray');
    } catch (_) {
      if (_isCurrent(operation)) {
        _setState(VmessProxyPhase.failure, stopFailureMessage);
      }
      return;
    }
    if (_isCurrent(operation)) _setState(VmessProxyPhase.inactive);
  }

  Future<int> _getFreePort() async {
    final data = await _bridge.invoke('getFreePorts', {'count': 1});
    if (data is! Map || data['ports'] is! List) {
      throw const XrayBridgeException();
    }
    final ports = data['ports'] as List;
    if (ports.length != 1 || ports.single is! int) {
      throw const XrayBridgeException();
    }
    return ports.single as int;
  }

  Future<bool> _waitUntilReady(int port, int operation) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (!_isCurrent(operation)) return false;
      final state = await _bridge.invoke('getXrayState');
      if (!_isCurrent(operation)) return false;
      final running = state is Map && state['running'] == true;
      if (running && await _portProbe(port)) {
        return _isCurrent(operation);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!_isCurrent(operation)) return false;
    }
    return false;
  }

  Future<void> _bestEffortStop() async {
    try {
      await _bridge.invoke('stopXray');
    } catch (_) {
      // 启动失败后的收尾不覆盖固定用户错误。
    }
  }

  static Map<String, Object?> _buildConfig({
    required int port,
    required String username,
    required String password,
    required Map<String, Object?> outbound,
  }) {
    final safeOutbound = Map<String, Object?>.from(outbound)
      ..remove('sendThrough')
      ..['tag'] = 'luma-vmess-out';
    return {
      'log': {'loglevel': 'warning'},
      'inbounds': [
        {
          'listen': '127.0.0.1',
          'port': port,
          'protocol': 'http',
          'tag': 'luma-http-in',
          'settings': {
            'auth': 'password',
            'accounts': [
              {'user': username, 'pass': password},
            ],
            'allowTransparent': false,
          },
        },
      ],
      'outbounds': [safeOutbound],
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {
            'type': 'field',
            'inboundTag': ['luma-http-in'],
            'outboundTag': 'luma-vmess-out',
          },
        ],
      },
    };
  }

  static Future<bool> _defaultPortProbe(int port) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 250),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _randomSecret(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  bool _isCurrent(int operation) => !_disposed && operation == _operation;

  void _setState(VmessProxyPhase phase, [String? message]) {
    _phase = phase;
    _message = message;
    if (!_disposed) notifyListeners();
  }

  Future<void> disposeProxy() async {
    if (_disposed) return;
    _disposed = true;
    _operation++;
    _route.deactivate();
    await _bestEffortStop();
    super.dispose();
  }
}
