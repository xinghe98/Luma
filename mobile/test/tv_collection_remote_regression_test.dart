// 完整分类列表的真实路由回归：验证查看全部后的遥控首焦点、网格滚动与详情返回。
// 测试独立创建仓库和路由；页面持有焦点生命周期，结束时先卸载页面再释放依赖。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_router.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/core/theme/tv_theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_collection_page.dart';
import 'package:luma/features/catalog/widgets/catalog_card.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/shared/layout/section_header.dart';
import 'package:luma/shared/media/media_card.dart';
import 'package:luma/shared/states/error_state.dart';

const _categories = [
  (title: '电影', path: '/videos/movies', personal: false),
  (title: '电视剧', path: '/videos/series', personal: false),
  (title: '个人视频', path: '/videos/personal', personal: true),
];

void main() {
  testWidgets('TV 分类入口同排，方向键切换后确认进入完整分类', (tester) async {
    final harness = await _mount(tester);
    final movie = find.byKey(const ValueKey('tv-category-movies'));
    final series = find.byKey(const ValueKey('tv-category-series'));
    final personal = find.byKey(const ValueKey('tv-category-personal'));
    expect(tester.getTopLeft(movie).dy, tester.getTopLeft(series).dy);
    expect(tester.getTopLeft(series).dy, tester.getTopLeft(personal).dy);
    // TV 壳层先用 Right 进入内容区；导航展开时内容不参与 Tab 遍历。
    await _press(tester, LogicalKeyboardKey.arrowRight);
    for (var step = 0; step < 24 && !_focusWithin(movie); step++) {
      await _press(tester, LogicalKeyboardKey.tab);
    }
    expect(_focusWithin(movie), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusWithin(series), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusWithin(personal), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focusWithin(series), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(_location(harness.router), '/videos/series');
    expect(_focusedCardId(), isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV 分类刷新失败仍显示作品和显式重试入口', (tester) async {
    final repository = _CatalogRepository()..fail = true;
    await _mount(
      tester,
      catalog: repository,
      location: '/videos/movies',
      initial: repository.movies,
    );
    expect(find.byType(CatalogCard), findsWidgets);
    expect(find.text('刷新失败'), findsOneWidget);
    final retry = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '重新刷新',
    );
    expect(retry, findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (var step = 0; step < 24 && !_focusWithin(retry); step++) {
      await _press(tester, LogicalKeyboardKey.tab);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(_focusWithin(retry), isTrue);
    repository.fail = false;
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('刷新失败'), findsNothing);
    expect(find.byType(CatalogCard), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final device in [
    (size: const Size(390, 844), tv: false, platform: TargetPlatform.android),
    (size: const Size(1280, 720), tv: true, platform: TargetPlatform.android),
    (size: const Size(1920, 1080), tv: true, platform: TargetPlatform.android),
    (size: const Size(1600, 900), tv: false, platform: TargetPlatform.windows),
  ]) {
    for (final category in _categories) {
      testWidgets(
        '${category.title} 查看全部 ${device.size} TV=${device.tv} ${device.platform}',
        (tester) async {
          final harness = await _mount(
            tester,
            size: device.size,
            tv: device.tv,
            platform: device.platform,
          );
          final header = find.byWidgetPredicate(
            (widget) =>
                widget is SectionHeader && widget.title == category.title,
          );
          final overview = find.byKey(
            const PageStorageKey('catalog-overview-scroll'),
          );
          await tester.scrollUntilVisible(
            header,
            300,
            scrollable: find
                .descendant(of: overview, matching: find.byType(Scrollable))
                .first,
          );
          await tester.pumpAndSettle();
          final openAll = find.descendant(
            of: header,
            matching: find.text('查看全部'),
          );
          await tester.ensureVisible(openAll);
          await tester.pumpAndSettle();
          await tester.tap(openAll);
          await tester.pumpAndSettle();
          expect(_location(harness.router), category.path);

          final page = find.byType(
            category.personal ? LibraryPage : CatalogCollectionPage,
          );
          final cards = find.descendant(
            of: page,
            matching: find.byType(category.personal ? MediaCard : CatalogCard),
          );
          expect(cards, findsWidgets);
          if (device.tv) {
            // 这里不调用 requestFocus：必须由真实路由把焦点交给可操作卡片。
            final initial = _focusedCardId();
            expect(initial, isNotNull);
            await _press(tester, LogicalKeyboardKey.arrowRight);
            expect(_focusedCardId(), isNot(initial));
            expect(_focusedCardId(), isNotNull);
            for (var row = 0; row < 3; row++) {
              await _press(tester, LogicalKeyboardKey.arrowDown);
            }
            final scroll = tester.widget<CustomScrollView>(
              find.descendant(
                of: page,
                matching: find.byType(CustomScrollView),
              ),
            );
            if (scroll.controller!.position.maxScrollExtent > 0) {
              expect(scroll.controller!.offset, greaterThan(0));
            }
            final focused = FocusManager.instance.primaryFocus!;
            final rect = tester.getRect(find.byWidget(focused.context!.widget));
            expect(rect.overlaps(Offset.zero & device.size), isTrue);
            final selected = _focusedCardId();
            expect(selected, isNotNull);
            await _press(tester, LogicalKeyboardKey.select);
            expect(
              _location(harness.router),
              '${category.personal ? '/media' : '/catalog'}/$selected',
            );
            await _press(tester, LogicalKeyboardKey.escape);
            expect(_location(harness.router), category.path);
            expect(_focusedCardId(), selected);
            await _press(tester, LogicalKeyboardKey.arrowLeft);
            final resumed = _focusedCardId();
            expect(resumed, isNotNull);
            await _press(tester, LogicalKeyboardKey.enter);
            expect(
              _location(harness.router),
              '${category.personal ? '/media' : '/catalog'}/$resumed',
            );
          } else if (device.platform == TargetPlatform.windows) {
            // Windows 保留标准键盘遍历；Tab 可到列表，Enter 仍打开真实详情。
            for (var tab = 0; tab < 12 && _focusedCardId() == null; tab++) {
              await _press(tester, LogicalKeyboardKey.tab);
            }
            final selected = _focusedCardId();
            expect(selected, isNotNull);
            await _press(tester, LogicalKeyboardKey.enter);
            expect(
              _location(harness.router),
              '${category.personal ? '/media' : '/catalog'}/$selected',
            );
          } else {
            final card = tester.widget(cards.first);
            final id = card is CatalogCard
                ? card.item.id
                : (card as MediaCard).item.id;
            await tester.tap(cards.first);
            await tester.pumpAndSettle();
            expect(
              _location(harness.router),
              '${category.personal ? '/media' : '/catalog'}/$id',
            );
            await tester.tap(
              category.personal
                  ? find.byType(BackButton)
                  : find.byTooltip('返回'),
            );
            await tester.pumpAndSettle();
            expect(_location(harness.router), category.path);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('TV 首帧保留传入作品，延迟刷新不抢弹窗输入焦点', (tester) async {
    final repository = _CatalogRepository();
    final pending = Completer<List<CatalogItem>>();
    repository.pending = pending.future;
    final harness = await _mount(
      tester,
      catalog: repository,
      location: '/videos/movies',
      initial: repository.movies,
      settle: false,
    );
    await tester.pump();
    expect(find.byType(CatalogCard), findsWidgets);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(_focusedCardId(), isNotNull);
    final pageContext = tester.element(find.byType(CatalogCollectionPage));
    final input = FocusNode(debugLabel: 'collection-dialog-input');
    addTearDown(input.dispose);
    unawaited(
      showDialog<void>(
        context: pageContext,
        builder: (_) =>
            AlertDialog(content: TextField(focusNode: input, autofocus: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(input.hasFocus, isTrue);
    pending.complete(repository.movies);
    await tester.pumpAndSettle();
    expect(input.hasFocus, isTrue);
    harness.router.pop();
    await tester.pumpAndSettle();
    expect(_focusedCardId(), isNotNull);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    final selected = _focusedCardId();
    await _press(tester, LogicalKeyboardKey.select);
    expect(_location(harness.router), '/catalog/$selected');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV 空列表加载失败可遥控重试，异步内容可继续打开', (tester) async {
    final repository = _CatalogRepository()..fail = true;
    final harness = await _mount(
      tester,
      catalog: repository,
      location: '/videos/movies',
    );
    expect(find.byType(ErrorState), findsOneWidget);
    for (var move = 0; move < 3 && !_focusedInside<ErrorState>(); move++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focusedInside<ErrorState>(), isTrue);
    repository.fail = false;
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byType(ErrorState), findsNothing);
    for (var move = 0; move < 3 && _focusedCardId() == null; move++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    final selected = _focusedCardId();
    expect(selected, isNotNull);
    await _press(tester, LogicalKeyboardKey.select);
    expect(_location(harness.router), '/catalog/$selected');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final category in _categories) {
    for (final systemBack in [false, true]) {
      testWidgets('TV ${category.title} 深链接返回影视库 system=$systemBack', (
        tester,
      ) async {
        final harness = await _mount(tester, location: category.path);
        if (systemBack) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
        } else {
          await _press(tester, LogicalKeyboardKey.goBack);
        }
        expect(_location(harness.router), '/videos');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

bool _focusWithin(Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final elements = finder.evaluate().toSet();
  var found = elements.contains(focused);
  focused.visitAncestorElements((element) {
    if (elements.contains(element)) found = true;
    return !found;
  });
  return found;
}

// pushNamed 保留浏览器地址时，仍以真实 Navigator 匹配栈断言当前页面。
String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

String? _focusedCardId() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorWidgetOfExactType<CatalogCard>()?.item.id ??
      context?.findAncestorWidgetOfExactType<MediaCard>()?.item.id;
}

bool _focusedInside<T extends Widget>() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<T>() !=
    null;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(
    key,
    physicalKey: key == LogicalKeyboardKey.goBack
        ? PhysicalKeyboardKey.escape
        : null,
  );
  await tester.pumpAndSettle();
}

Future<({GoRouter router, AppDependencies dependencies})> _mount(
  WidgetTester tester, {
  Size size = const Size(1280, 720),
  bool tv = true,
  TargetPlatform platform = TargetPlatform.android,
  _CatalogRepository? catalog,
  String location = '/videos',
  List<CatalogItem>? initial,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dependencies = AppDependencies(
    mediaRepository: MockMediaRepository(),
    catalogRepository: catalog ?? _CatalogRepository(),
    connectionService: MockConnectionService(),
    deviceProfile: tv ? AppDeviceProfile.television : AppDeviceProfile.standard,
  );
  dependencies.session.connect(
    const ServerProfile(
      name: 'fixture',
      address: 'http://fixture.local',
      token: 'fixture-token',
      hostName: 'fixture',
    ),
  );
  final router = createAppRouter(dependencies)..go(location, extra: initial);
  addTearDown(dependencies.dispose);
  addTearDown(router.dispose);
  final theme = LumaTheme.dark().copyWith(platform: platform);
  await tester.pumpWidget(
    AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(
        theme: tv ? applyTvTheme(theme) : theme,
        routerConfig: router,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return (router: router, dependencies: dependencies);
}

class _CatalogRepository implements CatalogRepository {
  final movies = List.generate(
    40,
    (index) => _catalog(CatalogKind.movie, index),
  );
  final series = List.generate(
    40,
    (index) => _catalog(CatalogKind.series, index),
  );
  bool fail = false;
  Future<List<CatalogItem>>? pending;

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async {
    if (fail) throw StateError('分类读取失败');
    if (pending != null) return pending!;
    return kind == CatalogKind.series ? series : movies;
  }

  @override
  Future<CatalogItem> detail(String id) async =>
      [...movies, ...series].firstWhere((item) => item.id == id);

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async => CatalogFavorite(favorite: favorite, revision: revision + 1);
}

CatalogItem _catalog(CatalogKind kind, int index) => CatalogItem(
  id: '${kind.name}-$index',
  sourceId: 'fixture',
  kind: kind,
  title: '${kind == CatalogKind.movie ? '电影' : '电视剧'} $index',
  year: 2026,
  mediaCount: 1,
  episodeCount: 0,
  completedCount: 0,
  playableMediaId: 'video-0',
  thumbnailUrl: '',
  posterUrl: '',
  durationMs: 60000,
  resolution: '1080p',
  progressMs: 0,
  completed: false,
  updatedAt: DateTime(2026),
);
