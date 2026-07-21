// Persists aliases without sending them to the backend.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'server_alias_store.dart';

final class SecureServerAliasStore implements ServerAliasStore {
  const SecureServerAliasStore(this._storage);

  static const _prefix = 'luma.server.alias.';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String origin) => _storage.read(key: _key(origin));

  @override
  Future<void> write(String origin, String alias) =>
      _storage.write(key: _key(origin), value: alias);

  @override
  Future<void> clear(String origin) => _storage.delete(key: _key(origin));

  static String _key(String origin) => '$_prefix${Uri.encodeComponent(origin)}';
}
