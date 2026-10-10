// 底部导航与搜索返回测试：四个主目的地槽位、指示器对齐、隐藏搜索分支的返回路径。
// 组件级用例驱动 AdaptiveAppNavigation，壳层用例走真实路由，验证 Back 与返回按钮。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_router.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/features/shell/app_destination.dart';
import 'package:luma/features/shell/widgets/adaptive_app_navigation.dart';

void main() {
  group('bottom navigation', () {
    testWidgets('390×844 恰好四个带文字的主目的地槽位', (tester) async {
      _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(const _NavigationHarness());
      await tester.pumpAndSettle();

      final surface = tester.getRect(
        find.byKey(const ValueKey('bottom-navigation-surface')),
      );
      expect(surface.width, 390);
      expect(
        find.byKey(const ValueKey('bottom-nav-slot-search')),
        findsNothing,
      );
      final slots = _slotRects(tester);
      expect(slots, hasLength(4));
      for (final entry in AppDestination.primaryDestinations.indexed) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('bottom-nav-${entry.$2.routeName}')),
            matching: find.text(entry.$2.label),
          ),
          findsOneWidget,
        );
        final slot = slots[entry.$1];
        expect(slot.width, closeTo(390 / 4, 0.01));
        expect(slot.height, greaterThanOrEqualTo(LumaLayout.minTapTarget));
      }
      expect(AppDestination.primaryDestinations.map((d) => d.label), [
        '首页',
        '影视',
        '照片',
        '设置',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点照片后激活照片分支，指示器居中于照片槽位', (tester) async {
      _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(const _NavigationHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('bottom-nav-photos')));
      await tester.pumpAndSettle();

      expect(
        find.text('content-${AppDestination.photos.index}'),
        findsOneWidget,
      );
      final photoSlot = tester.getRect(
        find.byKey(const ValueKey('bottom-nav-slot-photos')),
      );
      expect(
        (_indicatorRect(tester).center.dx - photoSlot.center.dx).abs(),
        lessThan(1),
      );
      expect(_slotSelected(tester, AppDestination.photos), isTrue);
    });

    testWidgets('320 宽窄屏标签不溢出', (tester) async {
      _setSurface(tester, const Size(320, 720));
      await tester.pumpWidget(const _NavigationHarness());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bottom-nav-settings')));
      await tester.pumpAndSettle();
      final surface = tester.getRect(
        find.byKey(const ValueKey('bottom-navigation-surface')),
      );
      final indicator = _indicatorRect(tester);
      expect(indicator.right, lessThanOrEqualTo(surface.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('仅在切换到新标签时触发轻触感', (tester) async {
      _setSurface(tester, const Size(390, 844));
      final calls = _recordPlatformCalls(tester);
      await tester.pumpWidget(const _NavigationHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('bottom-nav-photos')));
      await tester.pump();
      expect(_hapticCalls(calls), hasLength(1));
      await tester.tap(find.byKey(const ValueKey('bottom-nav-photos')));
      await tester.pump();
      expect(_hapticCalls(calls), hasLength(1));
    });

    testWidgets('减少动画时指示器一帧内到位', (tester) async {
      _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        const _NavigationHarness(disableAnimations: true),
      );
      final initialLeft = _indicatorRect(tester).left;
      await tester.tap(find.byKey(const ValueKey('bottom-nav-videos')));
      await tester.pump();
      await tester.pump();
      expect(_indicatorRect(tester).left, greaterThan(initialLeft));
      expect(
        tester
            .widget<TweenAnimationBuilder<double>>(
              find.byKey(
                const ValueKey('bottom-navigation-indicator-animation'),
              ),
            )
            .duration,
        Duration.zero,
      );
    });

    testWidgets('搜索分支上不画指示器、四项都未选中', (tester) async {
      _setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        _NavigationHarness(initialIndex: AppDestination.search.index),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('bottom-navigation-indicator')),
        findsNothing,
      );
      for (final destination in AppDestination.primaryDestinations) {
        expect(_slotSelected(tester, destination), isFalse);
      }
    });

    testWidgets('1280×800 Rail 只有四个主目的地，不重复放搜索入口', (tester) async {
      _setSurface(tester, const Size(1280, 800));
      final calls = _recordPlatformCalls(tester);
      await tester.pumpWidget(const _NavigationHarness());
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations, hasLength(4));
      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byIcon(Icons.search_rounded),
        ),
        findsNothing,
      );
      await tester.tap(find.text('照片'));
      await tester.pumpAndSettle();
      expect(
        find.text('content-${AppDestination.photos.index}'),
        findsOneWidget,
      );
      expect(_hapticCalls(calls), isEmpty);
    });
  });

  group('search return', () {
    testWidgets('首页顶栏搜索进入搜索分支，返回按钮回到首页', (tester) async {
      _setSurface(tester, const Size(390, 844));
      final harness = await _pumpShell(tester);

      await tester.tap(
        find
            .descendant(
              of: find.byType(Scaffold).first,
              matching: find.byTooltip('搜索'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(harness.currentPath, AppDestination.search.path);
      expect(
        find.byKey(const ValueKey('bottom-navigation-indicator')),
        findsNothing,
      );
      final back = find.byTooltip('返回');
      expect(back, findsOneWidget);

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(harness.currentPath, AppDestination.home.path);
    });

    testWidgets('照片分支 Ctrl+F 后系统 Back 回到照片', (tester) async {
      _setSurface(tester, const Size(390, 844));
      final harness = await _pumpShell(tester);

      await tester.tap(find.byKey(const ValueKey('bottom-nav-photos')));
      await tester.pumpAndSettle();
      expect(harness.currentPath, AppDestination.photos.path);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(harness.currentPath, AppDestination.search.path);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(harness.currentPath, AppDestination.photos.path);
    });
  });
}

void _setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<MethodCall> _recordPlatformCalls(WidgetTester tester) {
  final calls = <MethodCall>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

List<MethodCall> _hapticCalls(List<MethodCall> calls) => calls
    .where((call) => call.method == 'HapticFeedback.vibrate')
    .toList(growable: false);

List<Rect> _slotRects(WidgetTester tester) => AppDestination.primaryDestinations
    .map(
      (destination) => tester.getRect(
        find.byKey(ValueKey('bottom-nav-slot-${destination.routeName}')),
      ),
    )
    .toList(growable: false);

/// 指示器通过 Transform 平移，需要把平移量加回布局矩形才是实际绘制位置。
Rect _indicatorRect(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('bottom-navigation-indicator'));
  final rect = tester.getRect(finder);
  final translation = tester
      .widget<Transform>(finder)
      .transform
      .getTranslation();
  return rect.shift(Offset(translation.x, translation.y));
}

bool _slotSelected(WidgetTester tester, AppDestination destination) => tester
    .widget<Semantics>(
      find.byKey(ValueKey('bottom-nav-${destination.routeName}')),
    )
    .properties
    .selected!;

class _ShellHarness {
  _ShellHarness(this.router);

  final GoRouter router;

  String get currentPath => router.routerDelegate.currentConfiguration.uri.path;
}

/// 用 mock 依赖启动真实路由与壳层，不连接任何真实服务器。
Future<_ShellHarness> _pumpShell(WidgetTester tester) async {
  final dependencies = AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
  );
  dependencies.session.connect(
    const ServerProfile(
      name: 'server.local',
      address: 'http://server.local:8080',
      token: 'token',
      hostName: 'server.local',
    ),
  );
  final router = createAppRouter(dependencies)..go(AppDestination.home.path);
  addTearDown(router.dispose);
  addTearDown(dependencies.dispose);
  await tester.pumpWidget(
    AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(theme: LumaTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return _ShellHarness(router);
}

class _NavigationHarness extends StatefulWidget {
  const _NavigationHarness({
    this.disableAnimations = false,
    this.initialIndex = 0,
  });

  final bool disableAnimations;
  final int initialIndex;

  @override
  State<_NavigationHarness> createState() => _NavigationHarnessState();
}

class _NavigationHarnessState extends State<_NavigationHarness> {
  late var _selectedIndex = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: LumaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: widget.disableAnimations),
        child: AdaptiveAppNavigation(
          selectedIndex: _selectedIndex,
          onSelect: (value) => setState(() => _selectedIndex = value),
          content: Center(child: Text('content-$_selectedIndex')),
        ),
      ),
    );
  }
}
