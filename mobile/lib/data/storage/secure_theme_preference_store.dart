import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'theme_preference_store.dart';

/// 用安全存储保存主题模式；值存 ThemeMode.name，未知值按 null 处理。
final class SecureThemePreferenceStore implements ThemePreferenceStore {
  const SecureThemePreferenceStore(this._storage);

  static const _key = 'luma.theme.mode';
  final FlutterSecureStorage _storage;

  @override
  Future<ThemeMode?> read() async {
    final value = await _storage.read(key: _key);
    for (final mode in ThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  @override
  Future<void> write(ThemeMode mode) =>
      _storage.write(key: _key, value: mode.name);
}
