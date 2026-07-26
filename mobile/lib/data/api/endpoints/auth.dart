part of '../api_client.dart';

/// 认证端点只负责登录和登出；会话注入仍由 ApiSessionInterceptor 统一处理。
mixin _AuthEndpoints on _ApiTransport {
  Future<Map<String, dynamic>> login(
    String username,
    String password, {
    required String deviceName,
    String? deviceKey,
  }) => _json(
    'POST',
    _api('/auth/login'),
    data: {
      'username': username,
      'password': password,
      'device_name': deviceName,
      'device_key': ?deviceKey,
    },
  );

  Future<void> logout() => _empty('POST', _api('/auth/logout'));
}
