// 登录设备命名：移动端取真实机型，桌面端取机型/主机名并拼接系统用户名。
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'desktop_host_name.dart';

/// DeviceNameResolver 为一次登录提供安全、可展示的设备名称。
abstract interface class DeviceNameResolver {
  /// resolve 返回用于创建会话的设备名称；读取系统信息失败时必须提供兜底值。
  Future<String> resolve();
}

/// PlatformDeviceNameResolver 从系统设备信息生成会话显示名称。
/// 不采集硬件唯一标识；桌面用户名来自环境变量或 device_info。
final class PlatformDeviceNameResolver implements DeviceNameResolver {
  /// PlatformDeviceNameResolver 可注入设备信息读取器，便于测试和替换平台实现。
  PlatformDeviceNameResolver({DeviceInfoPlugin? deviceInfo})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

  @override
  Future<String> resolve() async {
    try {
      final name = switch (defaultTargetPlatform) {
        TargetPlatform.android => _androidName(await _deviceInfo.androidInfo),
        TargetPlatform.iOS => _iosName(await _deviceInfo.iosInfo),
        TargetPlatform.windows => _windowsName(await _deviceInfo.windowsInfo),
        TargetPlatform.macOS => _macName(await _deviceInfo.macOsInfo),
        TargetPlatform.linux => _linuxName(await _deviceInfo.linuxInfo),
        _ => '',
      };
      return _boundedName(name);
    } on Object {
      return _fallbackName();
    }
  }

  String _androidName(AndroidDeviceInfo info) =>
      _joinName(info.brand, info.model);

  String _iosName(IosDeviceInfo info) {
    final marketing = _iosMarketingModels[info.utsname.machine];
    if (marketing != null && marketing.isNotEmpty) return marketing;
    final modelName = info.modelName.trim();
    if (modelName.isNotEmpty) return modelName;
    final machine = info.utsname.machine.trim();
    return machine.isNotEmpty ? machine : info.model.trim();
  }

  String _windowsName(WindowsDeviceInfo info) {
    final model = info.computerName.trim().isNotEmpty
        ? info.computerName.trim()
        : localDesktopHostName();
    final user = info.userName.trim().isNotEmpty
        ? info.userName.trim()
        : localDesktopUserName();
    return _joinModelAndUser(model, user);
  }

  String _macName(MacOsDeviceInfo info) {
    final model = info.modelName.trim().isNotEmpty
        ? info.modelName.trim()
        : (info.computerName.trim().isNotEmpty
              ? info.computerName.trim()
              : localDesktopHostName());
    return _joinModelAndUser(model, localDesktopUserName());
  }

  String _linuxName(LinuxDeviceInfo info) {
    final model = info.prettyName.trim().isNotEmpty
        ? info.prettyName.trim()
        : localDesktopHostName();
    return _joinModelAndUser(model, localDesktopUserName());
  }

  String _fallbackName() {
    if (kIsWeb) return 'Luma Web';
    return 'Luma ${defaultTargetPlatform.name}';
  }

  String _boundedName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return _fallbackName();
    return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
  }
}

/// _joinModelAndUser 将机型与系统用户名拼为「机型 · 用户名」。
String _joinModelAndUser(String model, String user) {
  final m = model.trim();
  final u = user.trim();
  if (m.isEmpty) return u;
  if (u.isEmpty) return m;
  if (m.toLowerCase().contains(u.toLowerCase())) return m;
  return '$m · $u';
}

String _joinName(String brand, String model) {
  final normalizedBrand = brand.trim();
  final normalizedModel = model.trim();
  if (normalizedBrand.isEmpty) return normalizedModel;
  if (normalizedModel.isEmpty) return normalizedBrand;
  if (normalizedModel.toLowerCase().startsWith(normalizedBrand.toLowerCase())) {
    return normalizedModel;
  }
  return '$normalizedBrand $normalizedModel';
}

const _iosMarketingModels = <String, String>{
  'iPhone15,2': 'iPhone 14 Pro',
  'iPhone15,3': 'iPhone 14 Pro Max',
  'iPhone14,7': 'iPhone 14',
  'iPhone14,8': 'iPhone 14 Plus',
  'iPhone16,1': 'iPhone 15 Pro',
  'iPhone16,2': 'iPhone 15 Pro Max',
  'iPhone15,4': 'iPhone 15',
  'iPhone15,5': 'iPhone 15 Plus',
  'iPhone17,1': 'iPhone 16 Pro',
  'iPhone17,2': 'iPhone 16 Pro Max',
  'iPhone17,3': 'iPhone 16',
  'iPhone17,4': 'iPhone 16 Plus',
  'iPhone17,5': 'iPhone 16e',
  'iPhone18,1': 'iPhone 17 Pro',
  'iPhone18,2': 'iPhone 17 Pro Max',
  'iPhone18,3': 'iPhone 17',
};
