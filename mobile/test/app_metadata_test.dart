// 统一应用元数据测试确保配置源、生成常量和窄宽/宽屏设置入口保持一致。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_metadata.g.dart';
import 'package:luma/app/controllers/settings_controller.dart';
import 'package:luma/features/settings/widgets/application_settings_card.dart';

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

  testWidgets('设置入口在窄屏和宽屏均展示统一的名称与版本', (tester) async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in const [Size(320, 720), Size(1280, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApplicationSettingsCard(
              settings: settings,
              onClearCache: () {},
              onAbout: () {},
              onDisconnect: () {},
            ),
          ),
        ),
      );

      expect(find.text('关于${AppMetadata.displayName}'), findsOneWidget);
      expect(find.text('客户端版本 ${AppMetadata.version}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
