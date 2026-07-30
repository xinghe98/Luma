// 底部导航专项测试覆盖窄屏几何、选中槽位动画与减少动画模式。
// 测试通过 AdaptiveAppNavigation 驱动真实五分支配置，不替代路由状态测试。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/features/shell/app_destination.dart';
import 'package:luma/features/shell/widgets/adaptive_app_navigation.dart';

void main() {
  testWidgets('capsule navigation keeps five usable targets across widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in <double>[320, 390, 600]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(const _NavigationHarness());
      await tester.pumpAndSettle();

      final surface = tester.getRect(
        find.byKey(const ValueKey('bottom-navigation-surface')),
      );
      final surfaceDecoration =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('bottom-navigation-surface')),
                  )
                  .decoration
              as BoxDecoration;
      final content = tester.getRect(
        find.byKey(const ValueKey('navigation-test-content')),
      );
      expect(surface.height, 64);
      expect(surface.width, lessThanOrEqualTo(520));
      expect(surfaceDecoration.boxShadow, isNull);
      expect(content.height, greaterThan(680));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bottom-navigation-surface')),
          matching: find.byType(AnimatedPositioned),
        ),
        findsNothing,
      );

      final slots = _slotRects(tester);
      final indicator = _indicatorRect(tester);
      final selectedContent = tester.getRect(
        find.byKey(const ValueKey('bottom-nav-selected-content-home')),
      );
      expect(slots, hasLength(AppDestination.values.length));
      expect(indicator.height, 44);
      expect(indicator.width, lessThanOrEqualTo(88));
      expect(selectedContent.center.dx, closeTo(indicator.center.dx, 0.01));
      expect(selectedContent.center.dy, closeTo(indicator.center.dy, 0.01));
      for (final slot in slots) {
        expect(slot.height, 56);
        expect(slot.width, greaterThanOrEqualTo(LumaLayout.minTapTarget));
        expect(slot.width, closeTo(slots.first.width, 0.01));
      }
      _expectNoOverlap(slots);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bottom-nav-home')),
          matching: find.text('首页'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bottom-nav-photos')),
          matching: find.text('图片库'),
        ),
        findsNothing,
      );
      final selectedLabel = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('bottom-nav-home')),
          matching: find.text('首页'),
        ),
      );
      expect(selectedLabel.style?.fontFamily, LumaTypography.fontFamily);
      expect(selectedLabel.style?.fontSize, 13);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bottom-nav-home')),
          matching: find.byType(FadeTransition),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bottom-nav-home')),
          matching: find.byType(SlideTransition),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      final homeInk = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const ValueKey('bottom-nav-home')),
          matching: find.byType(InkWell),
        ),
      );
      expect(homeInk.splashFactory, NoSplash.splashFactory);
      expect(
        homeInk.overlayColor?.resolve(<WidgetState>{WidgetState.pressed}),
        Colors.transparent,
      );
    }
  });

  testWidgets('手机底部导航仅在切换标签时触发轻触感', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(const _NavigationHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bottom-nav-photos')));
    await tester.pump();
    expect(_hapticCalls(platformCalls), hasLength(1));
    expect(
      _hapticCalls(platformCalls).single.arguments,
      'HapticFeedbackType.selectionClick',
    );

    await tester.tap(find.byKey(const ValueKey('bottom-nav-photos')));
    await tester.pump();
    expect(_hapticCalls(platformCalls), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('bottom-nav-videos')));
    await tester.pump();
    expect(_hapticCalls(platformCalls), hasLength(2));
  });

  testWidgets('宽屏 NavigationRail 切换不触发手机触感', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(const _NavigationHarness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片库'));
    await tester.pump();

    expect(find.text('content-1'), findsOneWidget);
    expect(_hapticCalls(platformCalls), isEmpty);
  });

  testWidgets('indicator moves without relayout of destination slots', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const _NavigationHarness());
    await tester.pumpAndSettle();

    final initialIndicator = _indicatorRect(tester);
    final initialSettings = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-slot-settings')),
    );

    await tester.tap(find.byKey(const ValueKey('bottom-nav-settings')));
    await tester.pump();
    expect(find.text('content-4'), findsOneWidget);
    expect(_indicatorRect(tester).left, initialIndicator.left);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bottom-nav-settings')),
        matching: find.byKey(const ValueKey('unselected')),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('bottom-nav-selected-content-settings'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 110));

    final movingIndicator = _indicatorRect(tester);
    final movingSettings = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-slot-settings')),
    );
    expect(movingIndicator.left, greaterThan(initialIndicator.left));
    expect(movingSettings, initialSettings);
    _expectNoOverlap(_slotRects(tester), tolerance: 0.5);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 110));
    final settledIndicator = _indicatorRect(tester);
    final settledSettings = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-slot-settings')),
    );
    final settledContent = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-selected-content-settings')),
    );
    expect(settledIndicator.left, greaterThan(movingIndicator.left));
    expect(settledSettings, initialSettings);
    expect(
      settledContent.center.dx,
      closeTo(settledIndicator.center.dx, 0.01),
    );
    expect(
      settledContent.center.dy,
      closeTo(settledIndicator.center.dy, 0.01),
    );
    _expectNoOverlap(_slotRects(tester));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bottom-nav-settings')),
        matching: find.text('设置'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('home and settings capsules stay inside a narrow surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const _NavigationHarness());
    await tester.pumpAndSettle();

    final surface = tester.getRect(
      find.byKey(const ValueKey('bottom-navigation-surface')),
    );
    final homeIndicator = _indicatorRect(tester);
    expect(homeIndicator.left, greaterThanOrEqualTo(surface.left + 4));

    await tester.tap(find.byKey(const ValueKey('bottom-nav-settings')));
    await tester.pump();
    await tester.pump();
    await tester.pump(LumaMotion.navigation);

    final settingsIndicator = _indicatorRect(tester);
    expect(settingsIndicator.right, lessThanOrEqualTo(surface.right - 4));
    final settingsContent = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-selected-content-settings')),
    );
    expect(
      settingsContent.center.dx,
      closeTo(settingsIndicator.center.dx, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion moves the capsule without an intermediate frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const _NavigationHarness(disableAnimations: true),
    );

    final initialLeft = _indicatorRect(tester).left;
    await tester.tap(find.byKey(const ValueKey('bottom-nav-videos')));
    await tester.pump();
    expect(find.text('content-2'), findsOneWidget);
    expect(_indicatorRect(tester).left, initialLeft);
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
    expect(tester.takeException(), isNull);
  });
}

List<MethodCall> _hapticCalls(List<MethodCall> calls) => calls
    .where((call) => call.method == 'HapticFeedback.vibrate')
    .toList(growable: false);

List<Rect> _slotRects(WidgetTester tester) => AppDestination.values
    .map(
      (destination) => tester.getRect(
        find.byKey(ValueKey('bottom-nav-slot-${destination.routeName}')),
      ),
    )
    .toList(growable: false);

Rect _indicatorRect(WidgetTester tester) {
  final finder = find.byKey(
    const ValueKey('bottom-navigation-indicator'),
  );
  final rect = tester.getRect(finder);
  final translation = tester
      .widget<Transform>(finder)
      .transform
      .getTranslation();
  return rect.shift(Offset(translation.x, translation.y));
}

void _expectNoOverlap(List<Rect> slots, {double tolerance = 0.01}) {
  for (var index = 1; index < slots.length; index++) {
    expect(
      slots[index].left + tolerance,
      greaterThanOrEqualTo(slots[index - 1].right),
    );
  }
}

class _NavigationHarness extends StatefulWidget {
  const _NavigationHarness({this.disableAnimations = false});

  final bool disableAnimations;

  @override
  State<_NavigationHarness> createState() => _NavigationHarnessState();
}

class _NavigationHarnessState extends State<_NavigationHarness> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: LumaTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: widget.disableAnimations),
        child: AdaptiveAppNavigation(
          selectedIndex: _selectedIndex,
          onSelect: (value) => setState(() => _selectedIndex = value),
          content: SizedBox.expand(
            key: ValueKey('navigation-test-content'),
            child: Center(child: Text('content-$_selectedIndex')),
          ),
        ),
      ),
    );
  }
}
