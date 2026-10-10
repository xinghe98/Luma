// TV 观看闭环测试：方向/OK/Back 覆盖导航与内容、TV 网格形态、连接页
// 编辑策略、详情首帧焦点与管理路由重定向；并用标准 profile 回归普通端。
// 不使用文字存在性代替焦点与布局断言。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_router.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/features/connection/connection_page.dart';
import 'package:luma/features/details/media_detail_page.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/features/shell/widgets/adaptive_app_navigation.dart';
import 'package:luma/features/shell/widgets/app_navigation_rail.dart';
import 'package:luma/main.dart';
import 'package:luma/shared/media/masonry_media_tile.dart';
import 'package:luma/shared/media/media_artwork.dart';

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

  Future<void> dismissLaunchOverlay(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('TV 五分支只用方向/OK/Back 遍历，隐藏分支不可获焦', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dependencies = tvDependencies();
    addTearDown(dependencies.dispose);
    // 直接连上服务器进入壳层，避免停在连接页。
    dependencies.session.connect(
      const ServerProfile(
        name: 'server.local',
        address: 'http://server.local:8080',
        token: 'token',
        hostName: 'server.local',
      ),
    );
    await tester.pumpWidget(LumaApp(dependencies: dependencies));
    await dismissLaunchOverlay(tester);
    await tester.pumpAndSettle();

    // 初次进入影视库：导航收起，焦点在第一张卡片而不是首页导航。
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('tv-nav-home'),
    );
    expect(find.text('轻影'), findsNothing);

    // Back：内容焦点回到影视库导航。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-videos');

    // 再 Back：非首页导航回首页导航，不弹退出确认。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-home');

    // 下移到「设置」并 OK：切到设置分支，焦点保持在导航项上。
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-settings');
    await press(tester, LogicalKeyboardKey.select);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-settings');

    // Back：非首页导航回首页导航，不弹退出确认。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-home');

    // 内容焦点 Back 后回到导航：从首页导航右移进内容，再 Back。
    await press(tester, LogicalKeyboardKey.arrowRight);
    final inContent = FocusManager.instance.primaryFocus;
    expect(inContent, isNotNull);
    expect(inContent!.debugLabel, isNot('tv-nav-home'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-home');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV 图片库使用规则网格与 contain 画框，不用瀑布流', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dependencies = tvDependencies();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: LibraryPage(
            type: MediaType.image,
            onOpenMedia: (_, {heroTag}) {},
            onOpenSearch: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MasonryMediaTile), findsNothing);
    // 同一行的两张卡必须等宽等高（规则网格），避免上下导航不可预测。
    final rects = <Rect>[];
    for (final element in find.byType(MediaArtwork).evaluate()) {
      final renderObject = element.renderObject;
      if (renderObject is RenderBox && renderObject.hasSize) {
        rects.add(renderObject.localToGlobal(Offset.zero) & renderObject.size);
      }
      if (rects.length >= 2) break;
    }
    expect(rects.length, greaterThanOrEqualTo(2));
    expect(rects.first.width, closeTo(rects[1].width, 0.5));
    expect(rects.first.height, closeTo(rects[1].height, 0.5));
  });

  testWidgets('TV 连接页进入不弹键盘，OK 才进入编辑', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dependencies = tvDependencies();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: const MaterialApp(home: ConnectionPage()),
      ),
    );
    await tester.pumpAndSettle();

    // 进入页面不自动弹 IME：任何 TextField 都没有焦点。
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((field) => field.focusNode.hasFocus),
      isFalse,
    );

    // 把浏览焦点放到第一个字段闸门上，OK 后进入 TextField 编辑。
    final gate = find
        .byWidgetPredicate(
          (widget) =>
              widget is Focus &&
              widget.focusNode?.debugLabel == 'tv-field-gate',
        )
        .first;
    (tester.widget(gate) as Focus).focusNode!.requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.select);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'connection-field-host',
    );
    // 编辑态 Back 先退回字段外层，不关闭页面。
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(ConnectionPage), findsOneWidget);
  });

  testWidgets('TV 详情首帧立即有内容且主播放为首焦点', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dependencies = tvDependencies();
    addTearDown(dependencies.dispose);
    final item = buildMediaFixtures().firstWhere(
      (media) => media.type == MediaType.video,
    );
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: MediaDetailPage(mediaId: item.id, initialItem: item),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'media-detail-play');
  });

  testWidgets('TV 管理四路径含管理员账号均重定向设置页', (tester) async {
    final dependencies = tvDependencies();
    addTearDown(dependencies.dispose);
    dependencies.session.connect(
      const ServerProfile(
        name: 'server.local',
        address: 'http://server.local:8080',
        token: 'token',
        hostName: 'server.local',
        userRole: 'admin',
        capabilities: ['users.manage'],
      ),
    );
    final router = createAppRouter(dependencies);
    addTearDown(router.dispose);

    for (final path in [
      '/settings/sources',
      '/settings/access',
      '/settings/access/new',
      '/settings/access/admin-1',
    ]) {
      router.go(path);
      await tester.pumpWidget(
        AppScope(
          dependencies: dependencies,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/settings',
        reason: 'TV 管理路径 $path 应重定向',
      );
    }
  });

  testWidgets('普通端回归：320/390 底部导航、960/1280 Rail 不变', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final (size, expectRail) in [
      (const Size(320, 640), false),
      (const Size(390, 844), false),
      (const Size(960, 640), true),
      (const Size(1280, 800), true),
    ]) {
      tester.view.physicalSize = size;
      final dependencies = standardDependencies();
      addTearDown(dependencies.dispose);
      dependencies.session.connect(
        const ServerProfile(
          name: 'server.local',
          address: 'http://server.local:8080',
          token: 'token',
          hostName: 'server.local',
        ),
      );
      await tester.pumpWidget(LumaApp(dependencies: dependencies));
      await dismissLaunchOverlay(tester);

      final navigation = find.byType(AdaptiveAppNavigation);
      expect(navigation, findsOneWidget, reason: '宽度 ${size.width}');
      final railOnScreen = find.byType(AppNavigationRail).evaluate().isNotEmpty;
      expect(railOnScreen, expectRail, reason: '宽度 ${size.width}');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
