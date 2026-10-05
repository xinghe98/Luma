// 设备能力识别：区分普通触控/桌面设备与 Android TV，供依赖组装与呈现分支读取。
// 只在这里读取原生特征和构建参数；页面与组件不得各自探测平台。
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// AppDeviceProfile 描述当前设备的整体呈现形态。
enum AppDeviceProfile {
  /// 手机、平板与 Windows 桌面：触摸/鼠标为主的既有体验。
  standard,

  /// Android TV / Google TV / 电视盒子：十英尺观看与遥控器输入。
  television;

  bool get isTelevision => this == AppDeviceProfile.television;
}

/// 识别 TV 的 Android 系统特征；不满足全部缺失时保持普通形态。
const _televisionFeatures = <String>{
  'android.software.leanback',
  'android.hardware.type.television',
};

/// resolveAppDeviceProfile 在构建依赖前解析一次设备形态。
///
/// 只有 Android 可能返回 television；其他平台（含 Windows）即使
/// [forceTelevision] 为 true 也始终返回 standard。Android 上先看强制参数，
/// 再读取系统特征；读取插件失败时普通包回退 standard，强制 TV 包不受影响。
/// 不按屏幕宽度、外接键盘或鼠标存在与否识别 TV。
Future<AppDeviceProfile> resolveAppDeviceProfile({
  DeviceInfoPlugin? deviceInfo,
  TargetPlatform? platform,
  bool forceTelevision = const bool.fromEnvironment('LUMA_TV'),
}) async {
  final target = platform ?? defaultTargetPlatform;
  if (target != TargetPlatform.android) return AppDeviceProfile.standard;
  if (forceTelevision) return AppDeviceProfile.television;
  try {
    final info = await (deviceInfo ?? DeviceInfoPlugin()).androidInfo;
    final features = info.systemFeatures;
    if (features.any(_televisionFeatures.contains)) {
      return AppDeviceProfile.television;
    }
  } on Object {
    // 插件不可用时按普通设备处理，不阻断启动。
  }
  return AppDeviceProfile.standard;
}
