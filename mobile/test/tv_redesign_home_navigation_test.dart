// TV 重写回归验证覆盖式导航、方向键恢复与内容首屏，复用真实页面和内存依赖。
// 每例卸载后释放焦点及依赖，不恢复凭据，也不调用原生播放器。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/core/theme/tv_theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/home/home_page.dart';
import 'package:luma/features/home/widgets/home_header.dart';
import 'package:luma/features/home/widgets/horizontal_media_section.dart';
import 'package:luma/features/home/widgets/tv_home_feature.dart';
import 'package:luma/features/shell/widgets/tv_app_navigation.dart';
import 'package:luma/shared/interaction/tv_key_bindings.dart';
import 'package:luma/shared/media/media_card.dart';

void main() {
  for (final size in [const Size(960, 540), const Size(1280, 800)]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      for (final dark in [false, true]) {
        testWidgets('TV 菜单展开不挤动内容且返回恢复原动作 $size $scale $dark', (tester) async {
          _viewport(tester, size);
          final first = FocusNode();
          final second = FocusNode();
          addTearDown(first.dispose);
          addTearDown(second.dispose);
          var activations = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: applyTvTheme(dark ? LumaTheme.dark() : LumaTheme.light()),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: TvKeyBindings(child: child!),
              ),
              home: TvAppNavigation(
                selectedIndex: 0,
                onSelect: (_) {},
                content: Scaffold(
                  body: Center(
                    child: Column(
                      key: const ValueKey('stable-content'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          focusNode: first,
                          onPressed: () {},
                          child: const Text('第一项'),
                        ),
                        FilledButton(
                          focusNode: second,
                          onPressed: () => activations++,
                          child: const Text('第二项'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final expandedWidth = tester
              .getSize(find.byKey(const ValueKey('tv-navigation-drawer')))
              .width;
          final before = tester.getRect(
            find.byKey(const ValueKey('stable-content')),
          );
          await _press(tester, LogicalKeyboardKey.arrowRight);
          expect(first.hasPrimaryFocus, isTrue);
          expect(
            tester.getRect(find.byKey(const ValueKey('stable-content'))),
            before,
          );
          expect(
            tester
                .getSize(find.byKey(const ValueKey('tv-navigation-drawer')))
                .width,
            lessThan(expandedWidth),
          );
          await _press(tester, LogicalKeyboardKey.arrowDown);
          expect(second.hasPrimaryFocus, isTrue);
          await _press(tester, LogicalKeyboardKey.escape);
          expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-home');
          expect(
            tester.getRect(find.byKey(const ValueKey('stable-content'))),
            before,
          );
          await _press(tester, LogicalKeyboardKey.arrowRight);
          expect(second.hasPrimaryFocus, isTrue);
          await _press(tester, LogicalKeyboardKey.select);
          expect(activations, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final layout in [
    (size: const Size(320, 640), tv: false),
    (size: const Size(390, 844), tv: false),
    (size: const Size(1280, 800), tv: false),
    (size: const Size(960, 540), tv: true),
    (size: const Size(1280, 800), tv: true),
  ]) {
    testWidgets('首页按设备保留品牌头或使用内容首屏 ${layout.size} TV=${layout.tv}', (
      tester,
    ) async {
      _viewport(tester, layout.size);
      final dependencies = AppDependencies(
        mediaRepository: _HomeRepository(),
        connectionService: MockConnectionService(),
        deviceProfile: layout.tv
            ? AppDeviceProfile.television
            : AppDeviceProfile.standard,
      );
      addTearDown(dependencies.dispose);
      await dependencies.media.load();
      String? opened;
      await tester.pumpWidget(
        AppScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: layout.tv
                ? applyTvTheme(LumaTheme.dark())
                : LumaTheme.light(),
            home: HomePage(
              onOpenMedia: (item, {heroTag}) => opened = item.id,
              onOpenSearch: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (layout.tv) {
        expect(find.byType(HomeHeader), findsNothing);
        final feature = find.byType(TvHomeFeature);
        final shelf = find.byWidgetPredicate(
          (widget) =>
              widget is HorizontalMediaSection && widget.title == '继续观看',
        );
        expect(
          tester.getBottomLeft(feature).dy,
          lessThanOrEqualTo(tester.getTopLeft(shelf).dy),
        );
        final action = find.byKey(const ValueKey('tv-home-open-feature'));
        expect(action.hitTestable(), findsOneWidget);
        await tester.tap(action);
        expect(opened, 'resume');
      } else {
        expect(find.byType(TvHomeFeature), findsNothing);
        expect(find.byType(HomeHeader), findsOneWidget);
        final firstCard = find.byType(MediaCard).first;
        await tester.ensureVisible(firstCard);
        await tester.pumpAndSettle();
        await tester.tap(firstCard);
        expect(opened, 'resume');
      }
      expect(tester.takeException(), isNull);
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
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

class _HomeRepository extends MockMediaRepository {
  final _media = MediaItem(
    id: 'resume',
    title: '山间的清晨',
    type: MediaType.video,
    duration: const Duration(minutes: 42),
    resolution: '1080p',
    format: 'mp4',
    fileSize: '1 GB',
    directory: '/',
    tags: const [],
    addedAt: DateTime(2026),
    artSeed: 0,
    progress: 0.3,
  );

  @override
  Future<List<MediaItem>> loadMedia() async => [_media];

  @override
  Future<List<MediaItem>> loadContinueWatching() async => [_media];
}
