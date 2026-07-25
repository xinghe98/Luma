import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/controllers/media_controller.dart';
import '../../app/controllers/session_controller.dart';
import '../../data/models/server_profile.dart';
import '../../data/services/connection_service.dart';

enum ConnectionPhase { idle, loading, success, failure }

class ConnectionController extends ChangeNotifier {
  ConnectionController({
    required ConnectionService connectionService,
    required SessionController sessionController,
    required MediaController mediaController,
    Future<void> Function()? onConnected,
    this.successDelay = const Duration(milliseconds: 500),
  }) : _service = connectionService,
       _session = sessionController,
       _media = mediaController,
       _onConnected = onConnected;

  final ConnectionService _service;
  final SessionController _session;
  final MediaController _media;
  final Future<void> Function()? _onConnected;
  final Duration successDelay;
  ConnectionPhase _phase = ConnectionPhase.idle;
  String? _message;
  int _operation = 0;
  bool _disposed = false;

  ConnectionPhase get phase => _phase;
  String? get message => _message;

  /// 成功提示停留期间同样锁定表单，避免延迟提交与下一次连接交错。
  bool get isLoading =>
      _phase == ConnectionPhase.loading || _phase == ConnectionPhase.success;

  /// 登录成功后仅激活服务端会话，密码不会进入 SessionController。
  Future<void> connect(String address, LoginCredentials credentials) async {
    final operation = ++_operation;
    _phase = ConnectionPhase.loading;
    _message = null;
    notifyListeners();
    final result = await _service.login(address, credentials);
    if (_disposed || operation != _operation) return;
    switch (result) {
      case ConnectionResult.success:
        _phase = ConnectionPhase.success;
        _message = '连接成功，正在同步媒体库';
        notifyListeners();
        await Future<void>.delayed(successDelay);
        if (_disposed || operation != _operation) return;
        _session.connect(
          _service.connectedProfile ??
              ServerProfile(
                name: Uri.parse(address).host,
                address: address.trim(),
                token: _service.connectedProfile?.token ?? '',
                hostName: Uri.parse(address).host,
              ),
        );
        unawaited(_loadConnectedData(operation));
      case ConnectionResult.invalidAddress:
        _phase = ConnectionPhase.failure;
        _message = '请输入有效的服务器地址';
      case ConnectionResult.unauthorized:
        _phase = ConnectionPhase.failure;
        _message = '用户名或密码错误，或账号已停用';
      case ConnectionResult.unreachable:
        _phase = ConnectionPhase.failure;
        _message = '无法连接服务器，请检查地址和内网状态';
    }
    notifyListeners();
  }

  Future<bool> restore(String address, String sessionToken) async {
    final operation = ++_operation;
    final result = await _service.restore(address, sessionToken);
    if (_disposed || operation != _operation) return false;
    if (result != ConnectionResult.success) return false;
    final profile = _service.connectedProfile;
    if (profile == null) return false;
    _session.connect(profile);
    unawaited(_loadConnectedData(operation));
    return true;
  }

  Future<void> _loadConnectedData(int operation) async {
    await _media.load();
    if (_disposed || operation != _operation) return;
    await _onConnected?.call();
  }

  void reset() {
    _operation++;
    _phase = ConnectionPhase.idle;
    _message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    super.dispose();
  }
}
