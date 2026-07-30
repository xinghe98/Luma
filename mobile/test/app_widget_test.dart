import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/data/services/connection_service.dart';
import 'package:luma/data/storage/server_alias_store.dart';
import 'package:luma/features/catalog/catalog_page.dart';
import 'package:luma/features/catalog/widgets/catalog_card.dart';
import 'package:luma/features/connection/connection_page.dart';
import 'package:luma/features/connection/widgets/connection_brand_header.dart';
import 'package:luma/features/home/widgets/home_header.dart';
import 'package:luma/features/search/widgets/search_results.dart';
import 'package:luma/features/settings/settings_page.dart';
import 'package:luma/features/shell/widgets/adaptive_app_navigation.dart';
import 'package:luma/main.dart';
import 'package:luma/shared/branding/brand_mark.dart';
import 'package:luma/shared/media/masonry_media_tile.dart';

void main() {
  AppDependencies createDependencies() => AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
  );

  Future<void> dismissLaunchOverlay(WidgetTester tester) async {
    // 先让品牌资源预缓存完成，再推进最短展示时间。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
  }

  testWidgets('production app disposes the dependencies it creates', (
    tester,
  ) async {
    final app = LumaApp.production();
    await tester.pumpWidget(app);
    await tester.pumpWidget(const SizedBox.shrink());

    expect(app.dependencies.isDisposed, isTrue);
    expect(await app.dependencies.restoreSession(), isFalse);
  });

  testWidgets('应用使用中文 Material 默认语义', (tester) async {
    final dependencies = createDependencies();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(LumaApp(dependencies: dependencies));

    final context = tester.element(find.byType(ConnectionPage));
    final localizations = MaterialLocalizations.of(context);
    expect(localizations.backButtonTooltip, '返回');
    expect(localizations.refreshIndicatorSemanticLabel, '刷新');
  });

  testWidgets('connection page shows brand and validation feedback', (
    tester,
  ) async {
    await tester.pumpWidget(LumaApp(dependencies: createDependencies()));
    await dismissLaunchOverlay(tester);
    expect(find.text('连接你的轻影服务器'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('连接你的轻影服务器')).textAlign,
      TextAlign.left,
    );
    expect(
      tester
          .widget<BrandMark>(
            find.byWidgetPredicate(
              (widget) => widget is BrandMark && widget.height == 56,
            ),
          )
          .height,
      56,
    );
    expect(find.text('连接家庭服务器后，你的影像仍然只属于自己的网络。'), findsNothing);

    // IP 为空时拼不出合法地址。
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.tap(find.text('立即连接'));
    await tester.pump();
    expect(find.text('正在连接'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 950));
    expect(find.text('请输入有效的服务器地址'), findsOneWidget);
  });

  for (final (name, size, theme) in [
    ('手机浅色', const Size(390, 844), LumaTheme.light()),
    ('Windows 宽屏深色', const Size(1200, 800), LumaTheme.dark()),
  ]) {
    testWidgets('$name连接页横版 Logo 使用可见尺寸布局', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: ConnectionBrandHeader()),
        ),
      );

      final logoRect = tester.getRect(find.byType(BrandMark));
      expect(logoRect.height, 56);
      expect(logoRect.width, inInclusiveRange(160, 170));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('connection page uses HTTP without a protocol choice', (
    tester,
  ) async {
    final service = _RecordingConnectionService();
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: service,
    );
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(LumaApp(dependencies: dependencies));
    await dismissLaunchOverlay(tester);

    expect(find.text('连接协议'), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.10');
    await tester.enterText(find.byType(TextField).at(1), '8080');
    await tester.enterText(find.byType(TextField).at(2), 'test-token');
    await tester.tap(find.text('立即连接'));
    await tester.pump();

    expect(service.lastAddress, 'http://192.168.1.10:8080');
  });

  testWidgets('connection page unlocks after saved-session recovery ends', (
    tester,
  ) async {
    final dependencies = createDependencies();
    addTearDown(dependencies.dispose);
    dependencies.restoring.value = true;
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: const MaterialApp(home: ConnectionPage()),
      ),
    );

    expect(find.text('正在恢复已保存的服务器连接…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    dependencies.restoring.value = false;
    await tester.pump();

    expect(find.text('正在恢复已保存的服务器连接…'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('successful connection opens the five destination shell', (
    tester,
  ) async {
    await tester.pumpWidget(LumaApp(dependencies: createDependencies()));
    await dismissLaunchOverlay(tester);
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.10');
    await tester.enterText(find.byType(TextField).at(1), '8080');
    await tester.enterText(find.byType(TextField).at(2), 'test-user');
    await tester.enterText(find.byType(TextField).at(3), 'test-password');
    await tester.tap(find.text('立即连接'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(NavigationBar), findsNothing);
    for (final routeName in [
      'home',
      'photos',
      'videos',
      'search',
      'settings',
    ]) {
      expect(find.byKey(ValueKey('bottom-nav-$routeName')), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('bottom-navigation-surface')),
      findsOneWidget,
    );
    final homeFeedback = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('bottom-nav-home')),
        matching: find.byType(InkWell),
      ),
    );
    expect(homeFeedback.borderRadius, isNotNull);
    final selectedHomeIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('bottom-nav-home')),
        matching: find.byType(Icon),
      ),
    );
    expect(selectedHomeIcon.color, LumaColors.paper);
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

    final initialIndicatorLeft = _indicatorPaintLeft(tester);
    await tester.tap(find.byKey(const ValueKey('bottom-nav-photos')));
    await tester.pump();
    final photoScroll = find.byKey(
      const PageStorageKey('library-scroll-image-all'),
    );
    expect(
      tester.widget<CustomScrollView>(photoScroll).cacheExtent,
      0,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final movingIndicatorLeft = _indicatorPaintLeft(tester);
    expect(movingIndicatorLeft, greaterThan(initialIndicatorLeft));
    await tester.pump(const Duration(milliseconds: 110));
    final settledIndicatorLeft = _indicatorPaintLeft(tester);
    expect(settledIndicatorLeft, greaterThan(movingIndicatorLeft));
    // 库页 ensureLoaded → mock search 有短延迟。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(
      tester.widget<CustomScrollView>(photoScroll).cacheExtent,
      LumaLayout.scrollCacheExtent,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('图片库')),
      findsOneWidget,
    );
    final imageTiles = tester.widgetList<MasonryMediaTile>(
      find.byType(MasonryMediaTile),
    );
    expect(imageTiles, isNotEmpty);
    expect(find.textContaining('个项目'), findsNothing);
    expect(
      imageTiles.every((tile) => tile.item.type == MediaType.image),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('bottom-nav-videos')));
    await tester.pump();
    await tester.pump(LumaMotion.navigation);
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('影视库')),
      findsOneWidget,
    );
    expect(find.byType(TabBar), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.search_rounded),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('搜索')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('bottom-nav-settings')));
    await tester.pump();
    expect(find.textContaining('windows amd64'), findsOneWidget);
    expect(find.textContaining('Database: ok'), findsOneWidget);
  });

  testWidgets('home brand header keeps search usable on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var searchOpened = false;
    final dependencies = createDependencies();
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: LumaTheme.light(),
          home: Scaffold(
            body: SafeArea(
              child: HomeHeader(
                onOpenSearch: () => searchOpened = true,
                onScrollToTop: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final homeLogo = find.byWidgetPredicate(
      (widget) =>
          widget is BrandMark &&
          widget.variant == BrandMarkVariant.symbol &&
          widget.height == 52,
    );
    final greeting = find.textContaining('欢迎回来');
    expect(homeLogo, findsOneWidget);
    expect(greeting, findsOneWidget);
    final logoRect = tester.getRect(homeLogo);
    final greetingRect = tester.getRect(greeting);
    expect(logoRect.right, lessThan(greetingRect.left));
    expect(greetingRect.top, lessThan(logoRect.bottom));
    expect(greetingRect.bottom, greaterThan(logoRect.top));
    expect(find.text('搜索你的媒体'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('搜索你的媒体'));
    await tester.pump();
    expect(searchOpened, isTrue);
  });

  testWidgets('bottom navigation settles immediately with reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: LumaTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) => AdaptiveAppNavigation(
              selectedIndex: selectedIndex,
              onSelect: (value) => setState(() => selectedIndex = value),
              content: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final initialLeft = _indicatorPaintLeft(tester);
    await tester.tap(find.byKey(const ValueKey('bottom-nav-photos')));
    await tester.pump();
    await tester.pump();
    expect(_indicatorPaintLeft(tester), greaterThan(initialLeft));
    expect(find.text('图片库'), findsOneWidget);
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

  testWidgets('search idle state prompts for criteria', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchResults(
            items: const [],
            hasCriteria: false,
            searchState: LoadState.ready,
            onOpenMedia: (item, {heroTag}) {},
            onFavorite: (_) {},
            onClear: () {},
            onSearchRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('开始搜索'), findsOneWidget);
    expect(find.text('没有找到相关内容'), findsNothing);
  });

  testWidgets(
    'catalog overview loads television shelf when it is visible initially',
    (tester) async {
      final catalog = _CountingCatalogRepository();
      final dependencies = AppDependencies(
        mediaRepository: MockMediaRepository(),
        catalogRepository: catalog,
        connectionService: MockConnectionService(),
      );
      addTearDown(dependencies.dispose);
      await tester.pumpWidget(
        AppScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: CatalogPage(
              onOpenCatalog: (_, {heroTag}) {},
              onOpenPersonalMedia: (item, {heroTag}) {},
              onOpenSearch: () {},
              onOpenMovies: (_) {},
              onOpenSeries: (_) {},
              onOpenPersonalVideos: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final catalogScroll = find.byKey(
        const PageStorageKey('catalog-overview-scroll'),
      );
      expect(
        tester.widget<CustomScrollView>(catalogScroll).cacheExtent,
        0,
      );
      expect(catalog.calls, isEmpty);
      await tester.pump(LumaMotion.navigation);
      await tester.pump();
      expect(
        tester.widget<CustomScrollView>(catalogScroll).cacheExtent,
        LumaLayout.scrollCacheExtent,
      );
      expect(catalog.calls[CatalogKind.movie], 1);
      expect(catalog.calls[CatalogKind.series], 1);
      expect(dependencies.media.loadState, LoadState.idle);
    },
  );

  testWidgets('catalog shelf retains cards during refresh and refresh errors', (
    tester,
  ) async {
    final catalog = _ShelfRefreshCatalogRepository();
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      catalogRepository: catalog,
      connectionService: MockConnectionService(),
    );
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: CatalogPage(
            onOpenCatalog: (_, {heroTag}) {},
            onOpenPersonalMedia: (item, {heroTag}) {},
            onOpenSearch: () {},
            onOpenMovies: (_) {},
            onOpenSeries: (_) {},
            onOpenPersonalVideos: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(LumaMotion.navigation);
    await tester.pump();
    await tester.pump();
    expect(find.byType(CatalogCard), findsOneWidget);

    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final refreshing = refresh.onRefresh();
    await tester.pump();
    expect(find.byType(CatalogCard), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    catalog.failMovieRefresh();
    await refreshing;
    await tester.pump();
    expect(find.byType(CatalogCard), findsOneWidget);
    expect(find.text('刷新失败，当前保留上次内容'), findsOneWidget);
  });

  testWidgets('search reports search errors instead of empty results', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchResults(
            items: const [],
            hasCriteria: true,
            searchState: LoadState.error,
            onOpenMedia: (item, {heroTag}) {},
            onFavorite: (_) {},
            onClear: () {},
            onSearchRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('媒体库暂时不可用'), findsOneWidget);
    expect(find.text('没有找到相关内容'), findsNothing);
  });

  testWidgets('settings reflects a saved server alias immediately', (
    tester,
  ) async {
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: MockConnectionService(),
      aliasStore: _WidgetAliasStore(),
    );
    addTearDown(dependencies.dispose);
    dependencies.session.connect(
      const ServerProfile(
        name: 'server.local',
        address: 'http://server.local:8080',
        token: 'token',
        hostName: 'server.local',
      ),
    );
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    expect(find.text('server.local'), findsOneWidget);
    expect(find.text('待整理文件'), findsNothing);

    await dependencies.updateServerAlias('家庭服务器');
    await tester.pump();
    expect(find.text('家庭服务器'), findsOneWidget);
  });

  testWidgets('settings remains safe while a disconnect clears the server', (
    tester,
  ) async {
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: MockConnectionService(),
      aliasStore: _WidgetAliasStore(),
    );
    addTearDown(dependencies.dispose);
    dependencies.session.connect(
      const ServerProfile(
        name: 'server.local',
        address: 'http://server.local:8080',
        token: 'token',
        hostName: 'server.local',
      ),
    );
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    dependencies.session.disconnect();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('cancelling the server alias dialog does not throw', (
    tester,
  ) async {
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: MockConnectionService(),
      aliasStore: _WidgetAliasStore(),
    );
    addTearDown(dependencies.dispose);
    dependencies.session.connect(
      const ServerProfile(
        name: 'server.local',
        address: 'http://server.local:8080',
        token: 'token',
        hostName: 'server.local',
      ),
    );

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            dependencies.session,
            dependencies.settings,
            dependencies.restoring,
          ]),
          builder: (context, _) => const MaterialApp(home: SettingsPage()),
        ),
      ),
    );
    await tester.tap(find.byTooltip('编辑本地别名'));
    await tester.pumpAndSettle();
    expect(find.text('服务器别名'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(dependencies.session.server!.name, 'server.local');
  });

  testWidgets('server alias dialog keeps its three actions on one row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: MockConnectionService(),
      aliasStore: _WidgetAliasStore(),
    );
    addTearDown(dependencies.dispose);
    dependencies.session.connect(
      const ServerProfile(
        name: 'server.local',
        address: 'http://server.local:8080',
        token: 'token',
        hostName: 'server.local',
      ),
    );

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.tap(find.byTooltip('编辑本地别名'));
    await tester.pumpAndSettle();

    final restoreTop = tester.getTopLeft(find.text('恢复默认')).dy;
    final cancelTop = tester.getTopLeft(find.text('取消')).dy;
    final saveTop = tester.getTopLeft(find.text('保存')).dy;
    expect(cancelTop, restoreTop);
    expect(saveTop, restoreTop);
  });

  testWidgets('wide layout uses a navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dependencies = createDependencies();
    await tester.pumpWidget(LumaApp(dependencies: dependencies));
    unawaited(
      dependencies.connection.connect(
        'http://192.168.1.10:8096',
        const LoginCredentials(username: 'test', password: 'test-password'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(NavigationRail), findsOneWidget);
  });
}

class _WidgetAliasStore implements ServerAliasStore {
  final _values = <String, String>{};

  @override
  Future<void> clear(String origin) async {
    _values.remove(origin);
  }

  @override
  Future<String?> read(String origin) async => _values[origin];

  @override
  Future<void> write(String origin, String alias) async {
    _values[origin] = alias;
  }
}

double _indicatorPaintLeft(WidgetTester tester) {
  final finder = find.byKey(
    const ValueKey('bottom-navigation-indicator'),
  );
  final translation = tester
      .widget<Transform>(finder)
      .transform
      .getTranslation();
  return tester.getRect(finder).left + translation.x;
}

class _RecordingConnectionService implements ConnectionService {
  @override
  ServerProfile? connectedProfile;
  String? lastAddress;

  @override
  Future<void> disconnect() async {}

  @override
  Future<ConnectionResult> login(
    String address,
    LoginCredentials credentials,
  ) async {
    lastAddress = address;
    return ConnectionResult.invalidAddress;
  }

  @override
  Future<ConnectionResult> restore(String address, String sessionToken) =>
      login(
        address,
        const LoginCredentials(username: 'test', password: 'test-password'),
      );
}

class _CountingCatalogRepository implements CatalogRepository {
  final calls = <CatalogKind, int>{};

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async {
    if (kind != null) calls[kind] = (calls[kind] ?? 0) + 1;
    return const [];
  }

  @override
  Future<CatalogItem> detail(String id) => throw UnimplementedError();

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) => throw UnimplementedError();
}

class _ShelfRefreshCatalogRepository implements CatalogRepository {
  final _movieRefresh = Completer<List<CatalogItem>>();
  var movieCalls = 0;

  void failMovieRefresh() =>
      _movieRefresh.completeError(StateError('refresh failed'));

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async {
    if (kind != CatalogKind.movie) return [];
    movieCalls++;
    if (movieCalls > 1) return _movieRefresh.future;
    return [
      CatalogItem(
        id: 'movie-1',
        sourceId: 'source-1',
        kind: CatalogKind.movie,
        title: '保留的电影',
        year: 2026,
        mediaCount: 1,
        episodeCount: 0,
        completedCount: 0,
        playableMediaId: 'media-1',
        thumbnailUrl: '',
        posterUrl: '',
        durationMs: 3600000,
        resolution: '1080p',
        progressMs: 0,
        completed: false,
        updatedAt: DateTime(2026, 7, 26),
      ),
    ];
  }

  @override
  Future<CatalogItem> detail(String id) => throw UnimplementedError();

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) => throw UnimplementedError();
}
