// TV 设置/连接弹窗消费者行为测试：以遥控方向/OK/系统返回与触摸两条路径
// 验证别名弹窗、代理弹窗与开源许可页的真实交互——不测试源码或纯文字存在。
// 代理控制器使用内存 store 与受控原生桩，凭据不落盘。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/proxy/proxy_profile_store.dart';
import 'package:luma/data/proxy/proxy_route.dart';
import 'package:luma/data/proxy/vmess_proxy_controller.dart';
import 'package:luma/data/proxy/vmess_proxy_profile.dart';
import 'package:luma/data/proxy/xray_bridge.dart';
import 'package:luma/features/connection/widgets/vmess_proxy_control.dart';
import 'package:luma/features/settings/dialogs/about_luma_dialog.dart';
import 'package:luma/features/settings/dialogs/server_alias_dialog.dart';
import 'package:luma/features/shell/widgets/tv_field_gate.dart';

void main() {
  AppDependencies tvDependencies() => AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
    deviceProfile: AppDeviceProfile.television,
  );

  AppDependencies standardDependencies() => AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
  );

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  void useTvViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('TV 别名弹窗：打开不弹 IME，OK 才编辑，Back 先退编辑再关弹窗', (tester) async {
    useTvViewport(tester);
    final dependencies = tvDependencies();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: const MaterialApp(home: _AliasTrigger()),
      ),
    );

    await tester.tap(find.text('别名'));
    await tester.pumpAndSettle();

    // 打开弹窗：浏览焦点在字段外层闸门，系统 IME 未弹出。
    expect(find.text('服务器别名'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-field-gate');
    expect(tester.testTextInput.hasAnyClients, isFalse);

    // OK 进入编辑，输入生效。
    await press(tester, LogicalKeyboardKey.select);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    await tester.enterText(find.byType(TextField), '我的客厅');
    await tester.pumpAndSettle();

    // 系统返回：只退出编辑回到闸门，弹窗保持打开、IME 收起。
    await systemBack(tester);
    expect(find.text('服务器别名'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-field-gate');
    expect(tester.testTextInput.hasAnyClients, isFalse);

    // 再次返回：弹窗按取消语义关闭，无结果返回。
    await systemBack(tester);
    expect(find.text('服务器别名'), findsNothing);
    expect(find.textContaining('结果:'), findsNothing);

    // 重新打开编辑并经方向键到「保存」，结果回传触发页。
    await tester.tap(find.text('别名'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.select);
    await tester.enterText(find.byType(TextField), '我的客厅');
    await systemBack(tester);
    // 主按钮在字段下方，从闸门向下必落到三个动作按钮之一，向右可达「保存」。
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('结果:我的客厅'), findsOneWidget);
  });

  testWidgets('普通手机别名弹窗：触摸/键盘直编辑，不走 TV 闸门', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dependencies = standardDependencies();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: const MaterialApp(home: _AliasTrigger()),
      ),
    );

    await tester.tap(find.text('别名'));
    await tester.pumpAndSettle();

    // 普通端：字段自动聚焦并直接弹出 IME，无闸门包装。
    expect(find.byType(TvTextFieldGate), findsNothing);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    await tester.enterText(find.byType(TextField), '手机别名');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('结果:手机别名'), findsOneWidget);
  });

  testWidgets('TV 代理弹窗：不自动弹键盘，动作按钮≥56，Back 分层退出', (tester) async {
    useTvViewport(tester);
    final store = _MemoryProxyProfileStore();
    final bridge = XrayBridge(rawInvoker: _NativeStub().invoke);
    final controller = VmessProxyController(
      store: store,
      parser: VmessProfileParser(bridge),
      bridge: bridge,
      route: ProxyRoute(),
      portProbe: (_) async => true,
    );
    addTearDown(() => unawaited(controller.disposeProxy()));
    await controller.load();

    final dependencies = tvDependencies();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(home: _ProxyHost(controller: controller)),
      ),
    );
    await tester.tap(find.text('代理'));
    await tester.pumpAndSettle();

    expect(find.text('连接代理'), findsOneWidget);
    // 不自动弹出 IME，浏览焦点在链接字段外层闸门。
    expect(tester.testTextInput.hasAnyClients, isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-field-gate');

    // TV 动作按钮最小 56：主按钮与次级按钮都达到。
    final primarySize = tester.getSize(
      find.widgetWithText(FilledButton, '保存并启动'),
    );
    final cancelSize = tester.getSize(find.widgetWithText(TextButton, '取消'));
    expect(
      primarySize.height,
      greaterThanOrEqualTo(LumaTvLayout.controlMinHeight),
    );
    expect(
      cancelSize.height,
      greaterThanOrEqualTo(LumaTvLayout.controlMinHeight),
    );

    // OK 编辑并输入；系统返回只退编辑，弹窗保持打开。
    await press(tester, LogicalKeyboardKey.select);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    await tester.enterText(find.byType(TextField), 'vmess://tv-link');
    await systemBack(tester);
    expect(find.text('连接代理'), findsOneWidget);
    expect(tester.testTextInput.hasAnyClients, isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-field-gate');

    // 第二次返回才关闭弹窗；重开编辑后向下到主按钮完成连接。
    await systemBack(tester);
    expect(find.text('连接代理'), findsNothing);
    await tester.tap(find.text('代理'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.select);
    await tester.enterText(find.byType(TextField), 'vmess://tv-link');
    await systemBack(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text('连接代理'), findsNothing);
    expect(find.text('代理已开'), findsOneWidget);
  });

  testWidgets('TV 关于弹窗：许可页用真实 LicenseRegistry 内容，方向键滚动，返回焦点回触发按钮', (
    tester,
  ) async {
    useTvViewport(tester);
    final dependencies = tvDependencies();
    addTearDown(dependencies.dispose);
    // 仅注册测试许可：许可页展示的就是这些真实注册内容。
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    final longText = List.generate(
      120,
      (i) => '第 $i 段许可条款文本，用于撑起需要方向键滚动的长文。',
    ).join('\n\n');
    LicenseRegistry.addLicense(
      () => Stream.value(
        LicenseEntryWithLineBreaks(const ['pkg_alpha', 'pkg_beta'], longText),
      ),
    );
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showAboutLumaDialog(context),
                  child: const Text('关于'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(find.text('开源许可'), findsOneWidget);

    // TV 许可页推入后：展示注册的包列表与许可长文，焦点自动落在滚动区域。
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.text('pkg_alpha'), findsOneWidget);
    expect(find.text('pkg_beta'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv-license-scroll-region',
    );

    // 方向键滚动长文：视口位移大于 0。
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(scrollable.position.pixels, greaterThan(0));

    // 系统返回关闭许可页，焦点交回「开源许可」触发按钮。
    await systemBack(tester);
    expect(find.text('pkg_alpha'), findsNothing);
    expect(find.text('开源许可'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'about-license-button',
    );
  });

  testWidgets('宽屏普通端关于弹窗：开源许可仍打开系统 LicensePage', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dependencies = standardDependencies();
    addTearDown(dependencies.dispose);
    // 注册一条测试许可，避免许可页在测试环境加载 NOTICES 失败。
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    LicenseRegistry.addLicense(
      () => Stream.value(
        const LicenseEntryWithLineBreaks(['pkg_gamma'], '示例许可正文。'),
      ),
    );
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showAboutLumaDialog(context),
                  child: const Text('关于'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    // 普通端保持系统 LicensePage，不进入 TV 许可页分支。
    expect(find.byType(LicensePage), findsOneWidget);
  });
}

class _AliasTrigger extends StatefulWidget {
  const _AliasTrigger();

  @override
  State<_AliasTrigger> createState() => _AliasTriggerState();
}

class _AliasTriggerState extends State<_AliasTrigger> {
  String? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () async {
                final result = await showServerAliasDialog(context, '客厅电视');
                if (mounted) setState(() => _result = result);
              },
              child: const Text('别名'),
            ),
            if (_result != null) Text('结果:$_result'),
          ],
        ),
      ),
    );
  }
}

class _ProxyHost extends StatelessWidget {
  const _ProxyHost({required this.controller});

  final VmessProxyController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          VmessProxyAppBarAction(
            controller: controller,
            enabled: true,
            onStart: () async {
              await controller.start();
              return controller.isActive;
            },
            onStop: controller.stop,
            onImport: controller.importFromClipboard,
            onDelete: controller.deleteProfile,
          ),
        ],
      ),
      body: const SizedBox.shrink(),
    );
  }
}

/// 内存代理配置存储：不触碰 secure storage。
class _MemoryProxyProfileStore implements ProxyProfileStore {
  VmessProxyProfile? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<VmessProxyProfile?> read() async => value;

  @override
  Future<void> write(VmessProxyProfile profile) async => value = profile;
}

/// 受控原生桩：响应代理解析/端口/启停调用；与真实 XrayBridge 协议一致。
class _NativeStub {
  Future<String> invoke(String requestJson) async {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    switch (request['method']) {
      case 'convertShareLinksToXrayJson':
        return jsonEncode({
          'success': true,
          'data': {
            'outbounds': [
              {
                'protocol': 'vmess',
                'sendThrough': 'tv-node',
                'settings': {'address': 'private.example'},
              },
            ],
          },
          'error': '',
        });
      case 'getFreePorts':
        return jsonEncode({
          'success': true,
          'data': {
            'ports': [32123],
          },
          'error': '',
        });
      case 'getXrayState':
        return jsonEncode({
          'success': true,
          'data': {'running': true},
          'error': '',
        });
      case 'runXrayFromJson':
        return jsonEncode({'success': true, 'data': {}, 'error': ''});
      case 'stopXray':
        return jsonEncode({'success': true, 'data': {}, 'error': ''});
      default:
        return jsonEncode({'success': true, 'data': {}, 'error': ''});
    }
  }
}
