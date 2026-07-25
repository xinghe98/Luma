import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/data/services/connection_service.dart';
import 'package:luma/data/storage/server_alias_store.dart';
import 'package:luma/features/catalog/catalog_page.dart';
import 'package:luma/features/connection/connection_page.dart';
import 'package:luma/features/search/widgets/search_results.dart';
import 'package:luma/features/settings/settings_page.dart';
import 'package:luma/main.dart';
import 'package:luma/shared/branding/brand_mark.dart';
import 'package:luma/shared/media/masonry_media_tile.dart';

void main() {
  AppDependencies createDependencies() => AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
  );

  testWidgets('connection page shows brand and validation feedback', (
    tester,
  ) async {
    await tester.pumpWidget(LumaApp(dependencies: createDependencies()));
    expect(find.text('连接你的轻影服务器'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('连接你的轻影服务器')).textAlign,
      TextAlign.center,
    );
    expect(
      tester
          .widget<BrandMark>(
            find.byWidgetPredicate(
              (widget) => widget is BrandMark && widget.height == 72,
            ),
          )
          .height,
      72,
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
    await tester.enterText(find.byType(TextField).at(0), '192.168.1.10');
    await tester.enterText(find.byType(TextField).at(1), '8080');
    await tester.enterText(find.byType(TextField).at(2), 'test-token');
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
    final homeFeedback = tester.widget<InkResponse>(
      find.descendant(
        of: find.byKey(const ValueKey('bottom-nav-home')),
        matching: find.byType(InkResponse),
      ),
    );
    expect(homeFeedback.customBorder, isA<CircleBorder>());
    expect(homeFeedback.containedInkWell, isTrue);

    await tester.tap(find.byKey(const ValueKey('bottom-nav-photos')));
    await tester.pump();
    // 库页 ensureLoaded → mock search 有短延迟。
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('图片库')),
      findsOneWidget,
    );
    final imageTiles = tester.widgetList<MasonryMediaTile>(
      find.byType(MasonryMediaTile),
    );
    expect(imageTiles, isNotEmpty);
    expect(
      imageTiles.every((tile) => tile.item.type == MediaType.image),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('bottom-nav-videos')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
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
              onOpenCatalog: (_) {},
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

      expect(catalog.calls[CatalogKind.movie], 1);
      expect(catalog.calls[CatalogKind.series], 1);
      expect(dependencies.media.loadState, LoadState.idle);
    },
  );

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

  @override
  Future<void> ignore(String mediaId) => throw UnimplementedError();

  @override
  Future<List<CatalogIssue>> issues() => throw UnimplementedError();

  @override
  Future<void> updateMatch({
    required String mediaId,
    required CatalogKind kind,
    required String title,
    int? year,
    int? seasonNumber,
    int? episodeNumber,
  }) => throw UnimplementedError();
}
