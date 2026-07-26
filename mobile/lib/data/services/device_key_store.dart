// 安装级 device_key 存于应用私有安全存储，用于同机重登顶替旧会话，非硬件唯一标识。
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// DeviceKeyStore 读写本安装实例的稳定标识，不采集系统设备 ID。
abstract interface class DeviceKeyStore {
  /// readOrCreate 返回已有 key；首次调用时生成并持久化。
  Future<String> readOrCreate();
}

/// SecureDeviceKeyStore 使用 FlutterSecureStorage 保存安装级 UUID。
final class SecureDeviceKeyStore implements DeviceKeyStore {
  /// SecureDeviceKeyStore 可注入存储操作与随机源，便于测试。
  /// 仅插件缺失或平台明确不支持安全存储时退回进程内 key；读写故障会原样抛出。
  SecureDeviceKeyStore({
    FlutterSecureStorage? storage,
    Random? random,
    Future<String?> Function()? read,
    Future<void> Function(String value)? write,
  }) : _read =
           read ??
           (() => (storage ?? const FlutterSecureStorage()).read(key: _key)),
       _write =
           write ??
           ((value) => (storage ?? const FlutterSecureStorage()).write(
             key: _key,
             value: value,
           )),
       _random = random ?? Random.secure();

  static const _key = 'luma.device.key';

  final Future<String?> Function() _read;
  final Future<void> Function(String value) _write;
  final Random _random;
  String? _memoryFallback;
  Future<String>? _pending;

  @override
  Future<String> readOrCreate() async {
    final operation = _pending ??= _readOrCreate();
    try {
      return await operation;
    } finally {
      if (identical(_pending, operation)) _pending = null;
    }
  }

  Future<String> _readOrCreate() async {
    if (_memoryFallback case final fallback?) return fallback;
    try {
      final existing = await _read();
      if (existing != null && existing.trim().isNotEmpty) {
        return existing.trim();
      }
      final created = _newKey();
      await _write(created);
      return created;
    } on MissingPluginException {
      // 无插件的测试环境无法提供安全存储，只在当前进程复用 key。
      return _memoryFallback ??= _newKey();
    } on UnsupportedError {
      // 平台明确不支持插件时允许登录，但不会把降级 key 写入普通存储。
      return _memoryFallback ??= _newKey();
    }
  }

  String _newKey() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// MemoryDeviceKeyStore 仅用于测试的固定 device_key。
final class MemoryDeviceKeyStore implements DeviceKeyStore {
  MemoryDeviceKeyStore([this.value = 'test-device-key']);

  final String value;

  @override
  Future<String> readOrCreate() async => value;
}
