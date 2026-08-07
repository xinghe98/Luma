import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// 将随应用分发的原生核心许可加入 Flutter 的开源许可目录。
void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'libXray',
    ], await rootBundle.loadString('assets/licenses/libXray-MIT.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Xray-core',
    ], await rootBundle.loadString('assets/licenses/Xray-core-MPL-2.0.txt'));
  });
}
