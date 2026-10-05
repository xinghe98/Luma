// TV 焦点回归：真实壳层/分支路由、集合、字段闸门和启动遮罩共同维护可见操作焦点。
// 测试替换媒体与代理存储边界；路由、节点和控制器在每例卸载后释放，不运行原生服务。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/proxy/proxy_profile_store.dart';
import 'package:luma/data/proxy/proxy_route.dart';
import 'package:luma/data/proxy/vmess_proxy_controller.dart';
import 'package:luma/data/proxy/vmess_proxy_profile.dart';
import 'package:luma/data/proxy/xray_bridge.dart';
import 'package:luma/features/search/widgets/search_input.dart';
import 'package:luma/features/shell/app_destination.dart';
import 'package:luma/features/shell/app_shell.dart';
import 'package:luma/features/shell/widgets/branch_navigator_container.dart';
import 'package:luma/features/shell/widgets/tv_field_gate.dart';
import 'package:luma/main.dart';
import 'package:luma/shared/interaction/luma_focusable_surface.dart';
import 'package:luma/shared/interaction/tv_focus_collection.dart';
import 'package:luma/shared/interaction/tv_key_bindings.dart';

void main() {
  for (final destination in [
    AppDestination.home,
    AppDestination.search,
    AppDestination.settings,
  ]) {
    testWidgets(
      'first Right activates visible ${destination.routeName} content',
      (tester) async {
        _viewport(tester, const Size(1280, 720));
        final fixture = _ShellFixture(destination);
        addTearDown(fixture.dispose);
        await tester.pumpWidget(fixture.app);
        await tester.pumpAndSettle();
        expect(fixture.railNode(tester, destination).hasPrimaryFocus, isTrue);

        await _press(tester, LogicalKeyboardKey.arrowRight);
        expect(fixture.nodes[destination.index][0].hasPrimaryFocus, isTrue);
        expect(
          find.text('${destination.routeName}-0').hitTestable(),
          findsOneWidget,
        );
        await _press(tester, LogicalKeyboardKey.select);
        expect(fixture.activated, '${destination.routeName}-0');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'Left at a branch route boundary returns to its visible rail item',
    (tester) async {
      _viewport(tester, const Size(960, 720));
      final fixture = _ShellFixture(AppDestination.photos);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      // 独立建立边界前置状态，不让首进内容缺陷掩盖 Left 缺陷。
      fixture.nodes[AppDestination.photos.index][0].requestFocus();
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(
        fixture.railNode(tester, AppDestination.photos).hasPrimaryFocus,
        isTrue,
      );
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.select);
      expect(find.text('videos-0').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final back in ['Escape', 'remote Back', 'system Back']) {
    testWidgets('$back exits editing, returns to rail, Home, then exits app', (
      tester,
    ) async {
      _viewport(tester, const Size(1280, 720));
      var exits = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      final fixture = _ShellFixture(AppDestination.search, searchField: true);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      fixture.field.requestFocus();
      await tester.pumpAndSettle();
      expect(fixture.field.hasPrimaryFocus, isTrue);

      Future<void> pressBack() async {
        if (back == 'system Back') {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        } else {
          await _press(
            tester,
            back == 'Escape'
                ? LogicalKeyboardKey.escape
                : LogicalKeyboardKey.goBack,
          );
        }
      }

      await pressBack();
      expect(fixture.field.hasFocus, isFalse);
      expect(fixture.railNode(tester, AppDestination.search).hasFocus, isFalse);
      // 首次返回必须只退出编辑，OK 仍能立即重新编辑同一字段。
      await _press(tester, LogicalKeyboardKey.select);
      expect(fixture.field.hasPrimaryFocus, isTrue);
      await pressBack();
      await pressBack();
      expect(
        fixture.railNode(tester, AppDestination.search).hasPrimaryFocus,
        isTrue,
      );
      expect(exits, 0);
      await pressBack();
      expect(
        fixture.railNode(tester, AppDestination.home).hasPrimaryFocus,
        isTrue,
      );
      expect(find.text('home-0').hitTestable(), findsOneWidget);
      expect(exits, 0);
      await pressBack();
      expect(exits, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'returning to each branch restores its own last actionable card',
    (tester) async {
      _viewport(tester, const Size(1280, 720));
      final fixture = _ShellFixture(AppDestination.home);
      addTearDown(fixture.dispose);
      await tester.pumpWidget(fixture.app);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      fixture.nodes[0][1].requestFocus();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.select);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      fixture.nodes[1][0].requestFocus();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.select);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(fixture.nodes[0][1].hasPrimaryFocus, isTrue);
      expect(fixture.nodes[1].any((node) => node.hasFocus), isFalse);
      await _press(tester, LogicalKeyboardKey.select);
      expect(fixture.activated, 'home-1');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.select);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(fixture.nodes[1][0].hasPrimaryFocus, isTrue);
      expect(fixture.nodes[0].any((node) => node.hasFocus), isFalse);
      await _press(tester, LogicalKeyboardKey.select);
      expect(fixture.activated, 'photos-0');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('clearing old search results keeps the active query editable', (
    tester,
  ) async {
    final key = GlobalKey<_SearchHarnessState>();
    await tester.pumpWidget(_material(_SearchHarness(key: key)));
    final state = key.currentState!;
    state.result.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(state.field.hasPrimaryFocus, isTrue);
    tester.testTextInput.enterText('');
    await tester.pumpAndSettle();
    expect(find.text('旧结果'), findsNothing);
    expect(state.field.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    tester.testTextInput.enterText('新查询');
    await tester.pump();
    expect(state.query.text, '新查询');
    expect(find.text('新查询'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final retry in [false, true]) {
    testWidgets(
      'empty collection keeps a visible ${retry ? 'retry' : 'refresh'} target',
      (tester) async {
        final refresh = FocusNode();
        final retryNode = FocusNode();
        addTearDown(refresh.dispose);
        addTearDown(retryNode.dispose);
        String? activated;
        await tester.pumpWidget(
          _material(
            Column(
              children: [
                FilledButton(
                  focusNode: refresh,
                  autofocus: true,
                  onPressed: () => activated = 'refresh',
                  child: const Text('刷新'),
                ),
                Expanded(
                  child: TvFocusCollection(
                    itemIds: const [],
                    axis: Axis.vertical,
                    columns: 3,
                    revealIndex: (_) async {},
                    child: Center(
                      child: retry
                          ? FilledButton(
                              focusNode: retryNode,
                              onPressed: () => activated = 'retry',
                              child: const Text('重试'),
                            )
                          : const Text('暂无内容'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _press(tester, LogicalKeyboardKey.arrowDown);
        expect((retry ? retryNode : refresh).hasPrimaryFocus, isTrue);
        await _press(tester, LogicalKeyboardKey.select);
        expect(activated, retry ? 'retry' : 'refresh');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    're-registering a focused element moves Right from its visible ID',
    (tester) async {
      final ids = ValueNotifier<List<String>>(['A', 'B', 'C']);
      final nodes = List.generate(3, (_) => FocusNode());
      addTearDown(() {
        ids.dispose();
        for (final node in nodes) {
          node.dispose();
        }
      });
      String? activated;
      await tester.pumpWidget(
        _material(
          ValueListenableBuilder<List<String>>(
            valueListenable: ids,
            builder: (context, values, _) => TvFocusCollection(
              itemIds: values,
              axis: Axis.horizontal,
              columns: 1,
              revealIndex: (_) async {},
              child: Row(
                children: [
                  for (var index = 0; index < values.length; index++)
                    _card(
                      values[index],
                      nodes[index],
                      () => activated = values[index],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      nodes[1].requestFocus();
      await tester.pumpAndSettle();
      // 故意复用持焦元素，直接覆盖集合的已持焦注册契约，不依赖业务卡片 key。
      ids.value = ['B', 'A', 'C'];
      await tester.pumpAndSettle();
      expect(nodes[1].hasPrimaryFocus, isTrue);
      await _press(tester, LogicalKeyboardKey.select);
      expect(activated, 'A');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(nodes[2].hasPrimaryFocus, isTrue);
      await _press(tester, LogicalKeyboardKey.select);
      expect(activated, 'C');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'TV launch with a proxy action initially edits the address on OK',
    (tester) async {
      _viewport(tester, const Size(1280, 720));
      final dependencies = await _launchDependencies(
        AppDeviceProfile.television,
      );
      addTearDown(dependencies.dispose);
      await tester.pumpWidget(LumaApp(dependencies: dependencies));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await _press(tester, LogicalKeyboardKey.select);
      final address = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'IP 地址',
        ),
      );
      expect(address.focusNode!.hasPrimaryFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('192.168.1.24');
      await tester.pump();
      expect(address.controller!.text, '192.168.1.24');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets('standard launch keeps address tap editing at width $width', (
      tester,
    ) async {
      _viewport(tester, Size(width, 900));
      final dependencies = await _launchDependencies(AppDeviceProfile.standard);
      addTearDown(dependencies.dispose);
      await tester.pumpWidget(LumaApp(dependencies: dependencies));
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      final address = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'IP 地址',
      );
      await tester.tap(address);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('server.local');
      await tester.pump();
      expect(
        tester.widget<TextField>(address).controller!.text,
        'server.local',
      );
      expect(
        tester.widget<TextField>(address).focusNode!.hasPrimaryFocus,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(
    key,
    physicalKey: key == LogicalKeyboardKey.goBack
        ? PhysicalKeyboardKey.escape
        : null,
  );
  await tester.pumpAndSettle();
}

Widget _material(Widget child) => MaterialApp(
  home: TvKeyBindings(child: Scaffold(body: child)),
);

Widget _card(String id, FocusNode node, VoidCallback activate) =>
    LumaFocusableSurface(
      label: id,
      focusId: id,
      focusNode: node,
      borderRadius: BorderRadius.zero,
      onActivate: activate,
      child: SizedBox(width: 140, height: 80, child: Center(child: Text(id))),
    );

// 真实 StatefulShellRoute 保留嵌套 Navigator 的方向边界及分支生命周期。
class _ShellFixture {
  _ShellFixture(AppDestination initial, {bool searchField = false}) {
    router = GoRouter(
      initialLocation: initial.path,
      routes: [
        StatefulShellRoute(
          navigatorContainerBuilder: buildBranchNavigatorContainer,
          builder: (_, _, shell) => AppShell(navigationShell: shell),
          branches: [
            for (final destination in AppDestination.values)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: destination.path,
                    builder: (_, _) => Scaffold(
                      body: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (searchField &&
                              destination == AppDestination.search)
                            TvTextFieldGate(
                              fieldFocusNode: field,
                              builder: (_, _) => TextField(focusNode: field),
                            ),
                          TvFocusCollection(
                            itemIds: [
                              '${destination.routeName}-0',
                              '${destination.routeName}-1',
                            ],
                            axis: Axis.horizontal,
                            columns: 1,
                            revealIndex: (_) async {},
                            child: Row(
                              children: [
                                for (var index = 0; index < 2; index++)
                                  _card(
                                    '${destination.routeName}-$index',
                                    nodes[destination.index][index],
                                    () => activated =
                                        '${destination.routeName}-$index',
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  final dependencies = AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
    deviceProfile: AppDeviceProfile.television,
  );
  final nodes = List.generate(5, (_) => List.generate(2, (_) => FocusNode()));
  final field = FocusNode(skipTraversal: true);
  late final GoRouter router;
  String? activated;

  Widget get app => AppScope(
    dependencies: dependencies,
    child: MaterialApp.router(routerConfig: router),
  );

  FocusNode railNode(WidgetTester tester, AppDestination destination) => tester
      .widget<LumaFocusableSurface>(
        find.byWidgetPredicate(
          (widget) =>
              widget is LumaFocusableSurface &&
              widget.label == destination.label,
        ),
      )
      .focusNode!;

  void dispose() {
    router.dispose();
    dependencies.dispose();
    field.dispose();
    for (final branch in nodes) {
      for (final node in branch) {
        node.dispose();
      }
    }
  }
}

class _SearchHarness extends StatefulWidget {
  const _SearchHarness({super.key});

  @override
  State<_SearchHarness> createState() => _SearchHarnessState();
}

class _SearchHarnessState extends State<_SearchHarness> {
  final query = TextEditingController(text: '旧查询');
  final field = FocusNode(skipTraversal: true);
  final result = FocusNode();
  var hasResult = true;

  @override
  void dispose() {
    query.dispose();
    field.dispose();
    result.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TvTextFieldGate(
        fieldFocusNode: field,
        builder: (_, focused) => SearchInput(
          textController: query,
          focusNode: field,
          television: focused,
          onChanged: (_) => setState(() => hasResult = false),
          onSubmitted: (_) {},
          onClear: () {
            query.clear();
            setState(() => hasResult = false);
          },
        ),
      ),
      Expanded(
        child: TvFocusCollection(
          itemIds: hasResult ? const ['旧结果'] : const [],
          axis: Axis.horizontal,
          columns: 1,
          revealIndex: (_) async {},
          child: hasResult
              ? Align(
                  alignment: Alignment.topLeft,
                  child: _card('旧结果', result, () {}),
                )
              : const Center(child: Text('暂无结果')),
        ),
      ),
    ],
  );
}

Future<AppDependencies> _launchDependencies(AppDeviceProfile profile) async {
  final bridge = XrayBridge(
    rawInvoker: (_) async => throw StateError('焦点测试不应调用代理原生服务'),
  );
  final proxy = VmessProxyController(
    store: _EmptyProxyStore(),
    parser: VmessProfileParser(bridge),
    bridge: bridge,
    route: ProxyRoute(),
  );
  await proxy.load();
  return AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
    deviceProfile: profile,
    proxyController: proxy,
  );
}

final class _EmptyProxyStore implements ProxyProfileStore {
  @override
  Future<VmessProxyProfile?> read() async => null;

  @override
  Future<void> clear() async {}

  @override
  Future<void> write(VmessProxyProfile profile) async =>
      throw StateError('焦点测试不应写入代理配置');
}
