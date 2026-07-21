// Persists connection credentials in platform-provided secure storage.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credential_store.dart';

final class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore(this._storage);

  static const _originKey = 'luma.api.origin';
  static const _tokenKey = 'luma.api.token';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredCredentials?> read() async {
    final values = await _storage.readAll();
    final origin = values[_originKey];
    if (origin == null || origin.isEmpty) return null;
    return StoredCredentials(origin: origin, token: values[_tokenKey]);
  }

  @override
  Future<void> write(StoredCredentials credentials) async {
    await _storage.write(key: _originKey, value: credentials.origin);
    final token = credentials.token;
    if (token == null || token.isEmpty) {
      await _storage.delete(key: _tokenKey);
    } else {
      await _storage.write(key: _tokenKey, value: token);
    }
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _originKey),
      _storage.delete(key: _tokenKey),
    ]);
  }
}
