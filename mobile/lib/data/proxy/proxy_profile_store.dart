import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'vmess_proxy_profile.dart';

abstract interface class ProxyProfileStore {
  Future<VmessProxyProfile?> read();

  Future<void> write(VmessProxyProfile profile);

  Future<void> clear();
}

final class SecureProxyProfileStore implements ProxyProfileStore {
  const SecureProxyProfileStore(this._storage);

  static const _profileKey = 'luma.proxy.profile.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<VmessProxyProfile?> read() async {
    final encoded = await _storage.read(key: _profileKey);
    if (encoded == null) return null;
    try {
      return VmessProxyProfile.fromJson(jsonDecode(encoded));
    } catch (_) {
      throw const FormatException('已保存的代理配置无效');
    }
  }

  @override
  Future<void> write(VmessProxyProfile profile) {
    return _storage.write(
      key: _profileKey,
      value: jsonEncode(profile.toJson()),
    );
  }

  @override
  Future<void> clear() => _storage.delete(key: _profileKey);
}
