import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credential_store.dart';

final class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore(this._storage);

  static const _originKey = 'luma.api.origin';
  static const _legacyTokenKey = 'luma.api.token';
  static const _sessionKey = 'luma.api.session';
  static const _credentialsKey = 'luma.api.credentials.v2';

  final FlutterSecureStorage _storage;

  /// 优先读取单条原子凭据，并兼容升级前分键保存的会话。
  @override
  Future<StoredCredentials?> read() async {
    final values = await _storage.readAll();
    final encoded = values[_credentialsKey];
    if (encoded != null) {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('安全凭据格式无效');
      }
      final origin = decoded['origin'];
      final sessionToken = decoded['session_token'];
      if (origin is! String || origin.isEmpty) {
        throw const FormatException('安全凭据缺少服务地址');
      }
      if (sessionToken != null && sessionToken is! String) {
        throw const FormatException('安全凭据 token 格式无效');
      }
      return StoredCredentials(origin: origin, sessionToken: sessionToken);
    }

    final origin = values[_originKey];
    if (origin == null || origin.isEmpty) return null;
    // 旧 Token 认证已废弃，升级后必须重新登录。
    if (values[_sessionKey] == null && values[_legacyTokenKey] != null) {
      await _storage.delete(key: _legacyTokenKey);
      return null;
    }
    return StoredCredentials(origin: origin, sessionToken: values[_sessionKey]);
  }

  /// 以单条安全存储记录写入 origin/token；写入失败不会发布部分新凭据。
  @override
  Future<void> write(StoredCredentials credentials) async {
    // 单条安全存储写入避免 origin/token 分步更新产生部分凭据。
    await _storage.write(
      key: _credentialsKey,
      value: jsonEncode({
        'origin': credentials.origin,
        'session_token': credentials.sessionToken,
      }),
    );
  }

  /// 删除当前及历史凭据键；任一安全存储错误会向调用方报告。
  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _originKey),
      _storage.delete(key: _legacyTokenKey),
      _storage.delete(key: _sessionKey),
      _storage.delete(key: _credentialsKey),
    ]);
  }
}
