import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/storage/server_alias_store.dart';
import 'package:luma/features/search/widgets/search_results.dart';
import 'package:luma/features/settings/settings_page.dart';
import 'package:luma/main.dart';
import 'package:luma/shared/media/masonry_media_tile.dart';
import 'package:luma/shared/media/media_card.dart';

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

    // IP 为空时拼不出合法地址。
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.tap(find.text('立即连接'));
    await tester.pump();
    expect(find.text('正在连接'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 950));
    expect(find.textContaining('完整的 http://'), findsOneWidget);
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

    expect(find.byType(NavigationBar), findsOneWidget);
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      navigation.destinations.whereType<NavigationDestination>().map(
        (item) => item.label,
      ),
      ['首页', '图片库', '影音库', '搜索', '设置'],
    );

    await tester.tap(find.text('图片库'));
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

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('影音库'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('影音库')),
      findsOneWidget,
    );
    final videoCards = tester.widgetList<MediaCard>(find.byType(MediaCard));
    expect(videoCards, isNotEmpty);
    expect(
      videoCards.every((card) => card.item.type == MediaType.video),
      isTrue,
    );

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

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('设置'),
      ),
    );
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

  testWidgets('wide layout uses a navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dependencies = createDependencies();
    await tester.pumpWidget(LumaApp(dependencies: dependencies));
    unawaited(
      dependencies.connection.connect('http://192.168.1.10:8096', 'test-token'),
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
