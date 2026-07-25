import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credential_store.dart';

final class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore(this._storage);

  static const _originKey = 'luma.api.origin';
  static const _legacyTokenKey = 'luma.api.token';
  static const _sessionKey = 'luma.api.session';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredCredentials?> read() async {
    final values = await _storage.readAll();
    final origin = values[_originKey];
    if (origin == null || origin.isEmpty) return null;
    // 旧 Token 认证已废弃，升级后必须重新登录。
    if (values[_sessionKey] == null && values[_legacyTokenKey] != null) {
      await _storage.delete(key: _legacyTokenKey);
      return null;
    }
    return StoredCredentials(origin: origin, sessionToken: values[_sessionKey]);
  }

  @override
  Future<void> write(StoredCredentials credentials) async {
    await _storage.write(key: _originKey, value: credentials.origin);
    final token = credentials.sessionToken;
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _sessionKey);
    } else {
      await _storage.write(key: _sessionKey, value: token);
    }
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _originKey),
      _storage.delete(key: _legacyTokenKey),
      _storage.delete(key: _sessionKey),
    ]);
  }
}
