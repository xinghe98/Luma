// 统一应用元数据测试确保配置源与生成常量保持一致；设置页展示由 tv_forms_redesign_test 覆盖。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_metadata.g.dart';

void main() {
  test('生成的应用元数据与唯一配置源一致', () {
    final source =
        jsonDecode(File('app_metadata.json').readAsStringSync())
            as Map<String, Object?>;

    expect(AppMetadata.projectName, source['projectName']);
    expect(AppMetadata.displayName, source['displayName']);
    expect(AppMetadata.productName, source['productName']);
    expect(AppMetadata.androidApplicationId, source['androidApplicationId']);
    expect(AppMetadata.windowsExecutableName, source['windowsExecutableName']);
    expect(AppMetadata.companyName, source['companyName']);
    expect(AppMetadata.authorName, source['authorName']);
    expect(AppMetadata.copyright, source['copyright']);
    expect(
      '${AppMetadata.version}+${AppMetadata.buildNumber}',
      source['version'],
    );
  });
}
