// 搜索与媒体库回归：提交后可见结果的焦点交接、取消意图，以及各端刷新入口。
// 使用真实页面、控制器与内存仓库；Completer 控制响应时序，卸载页面后释放依赖。
import 'dart:async';

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
import 'package:luma/data/models/api_tag.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/features/search/search_page.dart';
import 'package:luma/features/search/widgets/search_filters.dart';
import 'package:luma/shared/interaction/tv_key_bindings.dart';
import 'package:luma/shared/media/masonry_media_tile.dart';
import 'package:luma/shared/media/media_card.dart';

void main() {
  for (final scenario in [
    (tags: 24, ready: true, dark: false, scale: 1.0),
    (tags: 64, ready: false, dark: true, scale: 1.3),
  ]) {
    testWidgets('TV 高标签区提交后先挂载并展示首条结果再允许确认 ${scenario.tags} 标签', (
      tester,
    ) async {
      final repository = _ControlledRepository(tagCount: scenario.tags);
      final dependencies = _dependencies(repository);
      addTearDown(dependencies.dispose);
      await dependencies.media.load();
      String? opened;
      await _mount(
        tester,
        dependencies,
        SearchPage(onOpenMedia: (item, {heroTag}) => opened = item.id),
        dark: scenario.dark,
        scale: scenario.scale,
      );
      await tester.enterText(find.byType(TextField), '海边');
      await tester.pump(const Duration(milliseconds: 350));
      expect(repository.requests, hasLength(1));
      final result = _item('search-first', MediaType.image);
      if (scenario.ready) {
        repository.requests.single.complete(
          MediaListPage(items: [result], nextCursor: null),
        );
        await tester.pumpAndSettle();
      }
      final viewport = tester.getRect(find.byType(CustomScrollView));
      expect(
        tester.getRect(find.byType(SearchFilters)).bottom,
        greaterThan(viewport.bottom),
        reason: '标签区必须真实超过视口，避免退化成短标题区测试',
      );
      expect(_card(result.id).hitTestable(), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      if (!scenario.ready) {
        repository.requests.single.complete(
          MediaListPage(items: [result], nextCursor: null),
        );
      }
      await tester.pumpAndSettle();

      final card = _card(result.id);
      expect(card, findsOneWidget);
      final rect = tester.getRect(card);
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(card.hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(opened, result.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('TV 后续输入取消未完成提交，旧结果不得滚动或抢走编辑焦点', (tester) async {
    final repository = _ControlledRepository(tagCount: 64);
    final dependencies = _dependencies(repository);
    addTearDown(dependencies.dispose);
    await dependencies.media.load();
    await _mount(
      tester,
      dependencies,
      SearchPage(onOpenMedia: (_, {heroTag}) {}),
    );
    await tester.enterText(find.byType(TextField), '旧查询');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.enterText(find.byType(TextField), '新查询');
    await tester.pump(const Duration(milliseconds: 350));
    expect(repository.requests, hasLength(2));
    repository.requests[1].complete(
      MediaListPage(
        items: [_item('new-query', MediaType.image)],
        nextCursor: null,
      ),
    );
    await tester.pumpAndSettle();
    repository.requests[0].complete(
      MediaListPage(
        items: [_item('old-query', MediaType.image)],
        nextCursor: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '新查询',
    );
    expect(_card('old-query'), findsNothing);
    expect(_card('new-query').hitTestable(), findsNothing);
    expect(_searchScroll(tester).offset, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV 离开搜索再返回取消未完成提交，不在返回后自动跳转旧结果', (tester) async {
    final repository = _ControlledRepository(tagCount: 64);
    final dependencies = _dependencies(repository);
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(dependencies.dispose);
    await dependencies.media.load();
    var routeActivations = 0;
    await _mount(
      tester,
      dependencies,
      SearchPage(onOpenMedia: (_, {heroTag}) {}),
      navigator: navigator,
    );
    await tester.enterText(find.byType(TextField), '海边');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: TextButton(
              autofocus: true,
              onPressed: () => routeActivations++,
              child: const Text('其他页面操作'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(routeActivations, 1);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.showKeyboard(find.byType(TextField));
    repository.requests.single.complete(
      MediaListPage(
        items: [_item('returned-result', MediaType.image)],
        nextCursor: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(_card('returned-result').hitTestable(), findsNothing);
    expect(_searchScroll(tester).offset, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('普通端搜索提交保留查询并可点击打开结果 $size', (tester) async {
      final repository = _ControlledRepository();
      final dependencies = _dependencies(repository, television: false);
      addTearDown(dependencies.dispose);
      String? opened;
      await _mount(
        tester,
        dependencies,
        SearchPage(onOpenMedia: (item, {heroTag}) => opened = item.id),
        size: size,
        dark: size.width > 600,
      );
      await tester.enterText(find.byType(TextField), '普通搜索');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      final item = _item('standard-search', MediaType.image);
      repository.requests.single.complete(
        MediaListPage(items: [item], nextCursor: null),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '普通搜索',
      );
      expect(_searchScroll(tester).offset, 0);
      await tester.ensureVisible(_card(item.id));
      await tester.pumpAndSettle();
      await tester.tap(_card(item.id));
      await tester.pump();
      expect(opened, item.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final type in [MediaType.image, MediaType.video]) {
    testWidgets('TV ${type.name} 库可遥控刷新，成功更新且失败保留可打开内容', (tester) async {
      final repository = _ControlledRepository();
      final dependencies = _dependencies(repository);
      addTearDown(dependencies.dispose);
      String? opened;
      await _mount(
        tester,
        dependencies,
        _library(type, (item, {heroTag}) => opened = item.id),
        dark: type == MediaType.video,
      );
      expect(repository.requests, hasLength(1));
      final old = _item('library-old', type);
      repository.requests[0].complete(
        MediaListPage(items: [old], nextCursor: null),
      );
      await tester.pumpAndSettle();
      expect(_card(old.id).hitTestable(), findsOneWidget);

      final refresh = find.byTooltip('刷新');
      expect(refresh.hitTestable(), findsOneWidget);
      await _focusWithTab(tester, find.byTooltip('搜索'));
      for (final direction in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        for (var step = 0; step < 5 && !_containsFocus(refresh); step++) {
          await tester.sendKeyEvent(direction);
          await tester.pump();
        }
        if (_containsFocus(refresh)) break;
      }
      expect(_containsFocus(refresh), isTrue, reason: '工具栏刷新必须能用方向键到达');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(repository.requests, hasLength(2));
      expect(_card(old.id).hitTestable(), findsOneWidget);
      final updated = _item('library-updated', type);
      repository.requests[1].complete(
        MediaListPage(items: [updated], nextCursor: null),
      );
      await tester.pumpAndSettle();
      expect(_card(updated.id).hitTestable(), findsOneWidget);
      expect(_card(old.id), findsNothing);

      await _focusWithTab(tester, refresh);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(repository.requests, hasLength(3));
      repository.requests[2].completeError(StateError('离线'));
      await tester.pumpAndSettle();
      expect(find.text('媒体库刷新失败'), findsOneWidget);
      expect(_card(updated.id).hitTestable(), findsOneWidget);
      await tester.tap(_card(updated.id));
      await tester.pump();
      expect(opened, updated.id);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final size in [const Size(390, 844), const Size(1280, 800)]) {
      testWidgets('普通端 ${type.name} 库保留下拉刷新与失败旧内容 $size', (tester) async {
        final repository = _ControlledRepository();
        final dependencies = _dependencies(repository, television: false);
        addTearDown(dependencies.dispose);
        String? opened;
        await _mount(
          tester,
          dependencies,
          _library(type, (item, {heroTag}) => opened = item.id),
          size: size,
          dark: size.width > 600,
        );
        final old = _item('touch-old', type);
        repository.requests.single.complete(
          MediaListPage(items: [old], nextCursor: null),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RefreshIndicator), findsOneWidget);
        await _pullToRefresh(tester);
        expect(repository.requests, hasLength(2));
        final updated = _item('touch-updated', type);
        repository.requests[1].complete(
          MediaListPage(items: [updated], nextCursor: null),
        );
        await tester.pumpAndSettle();
        expect(_card(updated.id).hitTestable(), findsOneWidget);
        expect(_card(old.id), findsNothing);
        await _pullToRefresh(tester);
        expect(repository.requests, hasLength(3));
        repository.requests[2].completeError(StateError('离线'));
        await tester.pumpAndSettle();
        expect(find.text('媒体库刷新失败'), findsOneWidget);
        expect(_card(updated.id).hitTestable(), findsOneWidget);
        await tester.tap(_card(updated.id));
        await tester.pump();
        expect(opened, updated.id);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

Future<void> _pullToRefresh(WidgetTester tester) async {
  await tester.dragFrom(
    tester.getTopLeft(find.byType(CustomScrollView)) + const Offset(30, 80),
    const Offset(0, 700),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

LibraryPage _library(
  MediaType type,
  void Function(MediaItem, {String? heroTag}) onOpen,
) => LibraryPage(
  type: type,
  fixedLibraryKind: type == MediaType.video ? 'personal' : null,
  title: type == MediaType.video ? '个人视频' : '图片库',
  onOpenMedia: onOpen,
  onOpenSearch: () {},
);

AppDependencies _dependencies(
  _ControlledRepository repository, {
  bool television = true,
}) => AppDependencies(
  mediaRepository: repository,
  connectionService: MockConnectionService(),
  deviceProfile: television
      ? AppDeviceProfile.television
      : AppDeviceProfile.standard,
);

Future<void> _mount(
  WidgetTester tester,
  AppDependencies dependencies,
  Widget page, {
  Size size = const Size(960, 540),
  bool dark = true,
  double scale = 1,
  GlobalKey<NavigatorState>? navigator,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final theme = dark ? LumaTheme.dark() : LumaTheme.light();
  await tester.pumpWidget(
    AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        navigatorKey: navigator,
        theme: dependencies.deviceProfile.isTelevision
            ? applyTvTheme(theme)
            : theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: TvKeyBindings(child: child!),
        ),
        home: page,
      ),
    ),
  );
  await tester.pump();
  // 库页在路由与壳层入场结束后的下一帧才启动请求。
  await tester.pump(LumaMotion.navigation);
  await tester.pump();
}

Finder _card(String id) => find.byWidgetPredicate(
  (widget) =>
      (widget is MediaCard && widget.item.id == id) ||
      (widget is MasonryMediaTile && widget.item.id == id),
);

ScrollController _searchScroll(WidgetTester tester) =>
    tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;

bool _containsFocus(Finder target) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final elements = target.evaluate().toSet();
  var found = elements.contains(focused);
  focused.visitAncestorElements((element) {
    if (elements.contains(element)) found = true;
    return !found;
  });
  return found;
}

Future<void> _focusWithTab(WidgetTester tester, Finder target) async {
  for (var step = 0; step < 40 && !_containsFocus(target); step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(_containsFocus(target), isTrue);
}

MediaItem _item(String id, MediaType type) => MediaItem(
  id: id,
  title: '媒体 $id',
  type: type,
  duration: const Duration(minutes: 2),
  resolution: '1080p',
  format: type == MediaType.image ? 'jpg' : 'mp4',
  fileSize: '1 MB',
  directory: '/',
  tags: const [],
  addedAt: DateTime(2026),
  artSeed: 1,
);

class _ControlledRepository extends MockMediaRepository {
  _ControlledRepository({this.tagCount = 0});

  final int tagCount;
  final requests = <Completer<MediaListPage>>[];

  @override
  Future<List<MediaItem>> loadMedia() async => const [];

  @override
  Future<List<MediaItem>> loadContinueWatching() async => const [];

  @override
  Future<int> countMedia({MediaType? type}) async => 0;

  @override
  Future<List<Tag>> loadTags() async => List.generate(
    tagCount,
    (index) => Tag(
      id: 'tag-$index',
      name: '旅行摄影素材分类标签 $index',
      usageCount: 1,
      revision: 1,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  );

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) {
    final request = Completer<MediaListPage>();
    requests.add(request);
    return request.future;
  }
}
