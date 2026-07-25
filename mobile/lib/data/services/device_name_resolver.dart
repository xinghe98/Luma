// 登录设备命名组件将移动端型号转换为本地营销名称，并为桌面端读取主机名。
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'desktop_host_name.dart';

/// DeviceNameResolver 为一次登录提供安全、可展示的设备名称。
abstract interface class DeviceNameResolver {
  /// resolve 返回用于创建会话的设备名称；读取系统信息失败时必须提供兜底值。
  Future<String> resolve();
}

/// PlatformDeviceNameResolver 从系统设备信息生成会话显示名称，不采集设备唯一标识。
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
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => localDesktopHostName(),
        _ => '',
      };
      return _boundedName(name);
    } on Object {
      return _fallbackName();
    }
  }

  String _androidName(AndroidDeviceInfo info) {
    final key = '${info.brand.toLowerCase()}:${info.model.toLowerCase()}';
    return _androidMarketingModels[key] ?? _joinName(info.brand, info.model);
  }

  String _iosName(IosDeviceInfo info) {
    return _iosMarketingModels[info.utsname.machine] ?? info.modelName;
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
};

const _androidMarketingModels = <String, String>{
  'xiaomi:23127pn0cc': 'Xiaomi 14 Pro',
  'xiaomi:23127pn0cg': 'Xiaomi 14 Pro',
  'xiaomi:23124ra7ec': 'Redmi K70',
  'xiaomi:23113rkc6c': 'Redmi K70E',
  'samsung:sm-s9180': 'Samsung Galaxy S23 Ultra',
  'samsung:sm-s9280': 'Samsung Galaxy S24 Ultra',
  'huawei:alt-al00': 'HUAWEI Mate 60 Pro',
  'oneplus:pjc110': 'OnePlus 12',
};
