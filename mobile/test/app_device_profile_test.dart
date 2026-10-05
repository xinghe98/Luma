// 设备形态解析测试：覆盖 TV 特征识别、强制参数、平台边界与插件失败回退。
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_device_profile.dart';

void main() {
  group('resolveAppDeviceProfile', () {
    test('non-Android platforms stay standard even when forced', () async {
      for (final platform in <TargetPlatform>[
        TargetPlatform.windows,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(
          await resolveAppDeviceProfile(
            deviceInfo: _FakeDeviceInfo(
              androidInfo: _androidInfoWith(const ['android.software.leanback']),
            ),
            platform: platform,
            forceTelevision: true,
          ),
          AppDeviceProfile.standard,
          reason: '$platform 即使强制参数为 true 也不能进入 TV',
        );
      }
    });

    test('Android with leanback feature resolves television', () async {
      expect(
        await resolveAppDeviceProfile(
          deviceInfo: _FakeDeviceInfo(
            androidInfo: _androidInfoWith(const [
              'android.software.leanback',
              'android.hardware.touchscreen',
            ]),
          ),
          platform: TargetPlatform.android,
        ),
        AppDeviceProfile.television,
      );
    });

    test('Android with television hardware type resolves television', () async {
      expect(
        await resolveAppDeviceProfile(
          deviceInfo: _FakeDeviceInfo(
            androidInfo: _androidInfoWith(const [
              'android.hardware.type.television',
            ]),
          ),
          platform: TargetPlatform.android,
        ),
        AppDeviceProfile.television,
      );
    });

    test('Android phone with big screen or keyboard stays standard', () async {
      expect(
        await resolveAppDeviceProfile(
          deviceInfo: _FakeDeviceInfo(
            androidInfo: _androidInfoWith(const [
              'android.hardware.touchscreen',
              'android.hardware.keyboard',
              'android.hardware.screen.landscape',
            ]),
          ),
          platform: TargetPlatform.android,
        ),
        AppDeviceProfile.standard,
      );
    });

    test('forced television wins on Android without TV features', () async {
      expect(
        await resolveAppDeviceProfile(
          deviceInfo: _FakeDeviceInfo(
            androidInfo: _androidInfoWith(const ['android.hardware.touchscreen']),
          ),
          platform: TargetPlatform.android,
          forceTelevision: true,
        ),
        AppDeviceProfile.television,
      );
    });

    test('plugin failure falls back to standard unless forced', () async {
      expect(
        await resolveAppDeviceProfile(
          deviceInfo: _FakeDeviceInfo(error: StateError('no plugin')),
          platform: TargetPlatform.android,
        ),
        AppDeviceProfile.standard,
      );
      expect(
        await resolveAppDeviceProfile(
          deviceInfo: _FakeDeviceInfo(error: StateError('no plugin')),
          platform: TargetPlatform.android,
          forceTelevision: true,
        ),
        AppDeviceProfile.television,
      );
    });
  });
}

AndroidDeviceInfo _androidInfoWith(List<String> features) =>
    AndroidDeviceInfo.fromMap(<String, dynamic>{
      'systemFeatures': features,
      'version': const <String, dynamic>{
        'codename': 'REL',
        'incremental': '1',
        'previewSdkInt': 0,
        'release': '14',
        'sdkInt': 34,
      },
      'board': 'test',
      'bootloader': 'test',
      'brand': 'test',
      'device': 'test',
      'display': 'test',
      'fingerprint': 'test',
      'hardware': 'test',
      'host': 'test',
      'id': 'test',
      'manufacturer': 'test',
      'model': 'test',
      'product': 'test',
      'tags': 'test',
      'type': 'test',
      'isPhysicalDevice': true,
      'freeDiskSize': 0,
      'totalDiskSize': 0,
      'serialNumber': 'test',
      'isLowRamDevice': false,
      'physicalRamSize': 0,
      'availableRamSize': 0,
    });

/// 测试用设备信息读取器：返回固定 Android 信息或抛出指定异常。
final class _FakeDeviceInfo extends DeviceInfoPlugin {
  _FakeDeviceInfo({AndroidDeviceInfo? androidInfo, Object? error})
    : _androidInfo = androidInfo,
      _error = error;

  final AndroidDeviceInfo? _androidInfo;
  final Object? _error;

  @override
  Future<AndroidDeviceInfo> get androidInfo {
    final error = _error;
    if (error != null) return Future.error(error);
    return Future.value(_androidInfo ?? AndroidDeviceInfo.fromMap(const {}));
  }
}
