import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'connection_form_store.dart';

final class SecureConnectionFormStore implements ConnectionFormStore {
  const SecureConnectionFormStore(this._storage);

  static const _formKey = 'luma.connection.form.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<SavedConnectionForm?> read() async {
    final encoded = await _storage.read(key: _formKey);
    if (encoded == null) return null;
    try {
      return SavedConnectionForm.fromJson(jsonDecode(encoded));
    } catch (_) {
      throw const FormatException('已保存的连接表单无效');
    }
  }

  @override
  Future<void> write(SavedConnectionForm form) {
    return _storage.write(key: _formKey, value: jsonEncode(form.toJson()));
  }

  @override
  Future<void> clear() => _storage.delete(key: _formKey);
}
