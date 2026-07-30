import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_router.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/api_access.dart';
import 'package:luma/data/models/api_source.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/repositories/media_repository.dart';
import 'package:luma/data/repositories/access_repository.dart';
import 'package:luma/data/repositories/source_repository.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/features/catalog/catalog_detail_page.dart';
import 'package:luma/features/catalog/widgets/catalog_card.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/features/player/widgets/player_scene.dart';
import 'package:luma/shared/states/skeleton.dart';

void main() {
  AppDependencies createDependencies({MediaRepository? mediaRepository}) =>
      AppDependencies(
        mediaRepository: mediaRepository ?? MockMediaRepository(),
        connectionService: MockConnectionService(),
      );

  Widget routedApp(
    AppDependencies dependencies,
    GoRouter router, {
    TargetPlatform platform = TargetPlatform.android,
    bool disableAnimations = false,
  }) => AppScope(
    dependencies: dependencies,
    child: MaterialApp.router(
      theme: ThemeData(platform: platform),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
    ),
  );

  CatalogItem catalogItem() => CatalogItem(
    id: 'catalog-transition',
    sourceId: 'source-1',
    kind: CatalogKind.movie,
    title: '过渡测试电影',
    year: 2026,
    mediaCount: 1,
    episodeCount: 0,
    completedCount: 0,
    playableMediaId: 'video-0',
    thumbnailUrl: '',
    posterUrl: '',
    durationMs: 3600000,
    resolution: '1080p',
    progressMs: 0,
    completed: false,
    updatedAt: DateTime(2026, 7, 26),
  );

  ServerProfile connectedProfile() => const ServerProfile(
    name: 'server.local',
    address: 'http://server.local:8080',
    token: 'token',
    hostName: 'server.local',
  );

  CustomTransitionPage<dynamic> detailTransitionPage(WidgetTester tester) =>
      tester
          .widgetList<Navigator>(find.byType(Navigator))
          .expand((navigator) => navigator.pages)
          .whereType<CustomTransitionPage<dynamic>>()
          .last;

  FadeTransition builtFade(
    WidgetTester tester,
    CustomTransitionPage<dynamic> page,
  ) =>
      page.transitionsBuilder(
            tester.element(find.byType(MaterialApp)),
            const AlwaysStoppedAnimation(0.5),
            kAlwaysDismissedAnimation,
            const SizedBox.shrink(),
          )
          as FadeTransition;

  testWidgets('protected deep link redirects an anonymous session to connect', (
    tester,
  ) async {
    final dependencies = createDependencies();
    final router = createAppRouter(dependencies)..go('/media/missing');
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(routedApp(dependencies, router));
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/connect');
    expect(find.text('连接你的轻影服务器'), findsOneWidget);
  });

  testWidgets('session restore returns to the protected deep link', (
    tester,
  ) async {
    final dependencies = createDependencies();
    final router = createAppRouter(dependencies)
      ..go('/media/video-0?from=share');
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(routedApp(dependencies, router));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/connect');

    dependencies.session.connect(connectedProfile());
    await tester.pump();
    await tester.pump(LumaMotion.normal);

    expect(router.routeInformationProvider.value.uri.path, '/media/video-0');
    expect(
      router.routeInformationProvider.value.uri.queryParameters['from'],
      'share',
    );
  });

  testWidgets(
    'an authenticated media detail deep link stays outside the tab shell',
    (tester) async {
      final dependencies = createDependencies();
      dependencies.session.connect(
        const ServerProfile(
          name: 'server.local',
          address: 'http://server.local:8080',
          token: 'token',
          hostName: 'server.local',
        ),
      );
      final router = createAppRouter(dependencies)..go('/media/missing');
      addTearDown(router.dispose);
      addTearDown(dependencies.dispose);

      await tester.pumpWidget(routedApp(dependencies, router));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('媒体详情'), findsOneWidget);
      expect(find.byKey(const ValueKey('bottom-nav-home')), findsNothing);
    },
  );

  testWidgets('media detail deep link keeps its skeleton until load settles', (
    tester,
  ) async {
    final repository = _BlockingDetailMediaRepository();
    final dependencies = createDependencies(mediaRepository: repository);
    dependencies.session.connect(connectedProfile());
    final cached = buildMediaFixtures().first;
    dependencies.media.remember(cached);
    final router = createAppRouter(dependencies)..go('/media/${cached.id}');
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(routedApp(dependencies, router));
    await tester.pump();
    await tester.pump();

    expect(repository.detailCalls, 1);
    expect(find.byType(DetailPageSkeleton), findsOneWidget);
    expect(find.text('重试'), findsNothing);

    repository.completeError(StateError('媒体读取失败'));
    await tester.pump();
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets(
    'an authenticated movie collection deep link opens its full list',
    (tester) async {
      final dependencies = createDependencies();
      dependencies.session.connect(
        const ServerProfile(
          name: 'server.local',
          address: 'http://server.local:8080',
          token: 'token',
          hostName: 'server.local',
        ),
      );
      final router = createAppRouter(dependencies)..go('/videos/movies');
      addTearDown(router.dispose);
      addTearDown(dependencies.dispose);

      await tester.pumpWidget(routedApp(dependencies, router));
      await tester.pump();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('电影')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('bottom-nav-videos')), findsNothing);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('video detail uses the same fade on ${platform.name}', (
      tester,
    ) async {
      final dependencies = createDependencies();
      dependencies.session.connect(connectedProfile());
      final router = createAppRouter(dependencies);
      addTearDown(router.dispose);
      addTearDown(dependencies.dispose);

      await tester.pumpWidget(
        routedApp(dependencies, router, platform: platform),
      );
      await tester.pump();
      router.pushNamed<void>(
        AppRoute.mediaDetail,
        pathParameters: const {'mediaId': 'video-0'},
        extra: const MediaDetailRouteData(useLightTransition: true),
      );
      await tester.pump();

      final page = detailTransitionPage(tester);
      expect(page.transitionDuration, LumaMotion.normal);
      expect(page.reverseTransitionDuration, LumaMotion.normal);
      final halfway = builtFade(tester, page).opacity.value;
      expect(halfway, greaterThan(0));
      expect(halfway, lessThan(1));

      await tester.pump(LumaMotion.normal);
    });
  }

  testWidgets('catalog detail uses the shared fade transition', (tester) async {
    final dependencies = createDependencies();
    dependencies.session.connect(connectedProfile());
    final router = createAppRouter(dependencies);
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(routedApp(dependencies, router));
    await tester.pump();
    router.pushNamed<void>(
      AppRoute.catalogDetail,
      pathParameters: const {'catalogId': 'catalog-transition'},
      extra: CatalogDetailRouteData(initialItem: catalogItem()),
    );
    await tester.pump();

    final page = detailTransitionPage(tester);
    expect(page.transitionDuration, LumaMotion.normal);
    expect(page.reverseTransitionDuration, LumaMotion.normal);
    final halfway = builtFade(tester, page).opacity.value;
    expect(halfway, greaterThan(0));
    expect(halfway, lessThan(1));
    await tester.pump(LumaMotion.normal);
  });

  testWidgets('catalog card detail leaves motion to its poster Hero', (
    tester,
  ) async {
    final dependencies = createDependencies();
    dependencies.session.connect(connectedProfile());
    final router = createAppRouter(dependencies);
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(routedApp(dependencies, router));
    await tester.pump();
    router.pushNamed<void>(
      AppRoute.catalogDetail,
      pathParameters: const {'catalogId': 'catalog-transition'},
      extra: CatalogDetailRouteData(
        initialItem: catalogItem(),
        heroTag: 'catalog-movie-catalog-transition',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final page = detailTransitionPage(tester);
    const child = SizedBox(key: ValueKey('catalog-hero-transition-child'));
    final built = page.transitionsBuilder(
      tester.element(find.byType(MaterialApp)),
      const AlwaysStoppedAnimation(0.5),
      kAlwaysDismissedAnimation,
      child,
    );
    expect(identical(built, child), isTrue);
    final posterHero = tester.widget<Hero>(
      find.descendant(
        of: find.byType(CatalogDetailPage),
        matching: find.byType(Hero),
      ),
    );
    expect(posterHero.createRectTween, CatalogCard.straightRectTween);
    await tester.pump(LumaMotion.normal);
  });

  testWidgets('personal video collection defers its 18-item page request', (
    tester,
  ) async {
    final repository = _RecordingPagingMediaRepository();
    final dependencies = createDependencies(mediaRepository: repository);
    dependencies.session.connect(connectedProfile());
    final router = createAppRouter(dependencies);
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);
    final item = buildMediaFixtures().firstWhere(
      (entry) => entry.type == MediaType.video,
    );

    await tester.pumpWidget(routedApp(dependencies, router));
    await tester.pump();
    router.pushNamed<void>(AppRoute.personalVideos, extra: [item]);
    await tester.pump();

    final page = detailTransitionPage(tester);
    final built = page.transitionsBuilder(
      tester.element(find.byType(MaterialApp)),
      const AlwaysStoppedAnimation(0.5),
      kAlwaysDismissedAnimation,
      const SizedBox.shrink(),
    );
    expect(built, isA<FadeTransition>());
    expect(repository.searchCalls, 0);

    await tester.pumpAndSettle();
    expect(repository.searchCalls, 1);
    expect(repository.limits, [18]);
  });

  testWidgets('photo branch uses the same 18-item page size', (tester) async {
    final dependencies = createDependencies();
    dependencies.session.connect(connectedProfile());
    final router = createAppRouter(dependencies)..go('/photos');
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      routedApp(dependencies, router, disableAnimations: true),
    );
    await tester.pump();

    final page = tester.widget<LibraryPage>(find.byType(LibraryPage));
    expect(page.pageSize, 18);
    await tester.pumpAndSettle();
  });

  testWidgets('image detail route leaves motion to its Hero only', (
    tester,
  ) async {
    final dependencies = createDependencies();
    dependencies.session.connect(connectedProfile());
    final router = createAppRouter(dependencies);
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(routedApp(dependencies, router));
    await tester.pump();
    router.pushNamed<void>(
      AppRoute.mediaDetail,
      pathParameters: const {'mediaId': 'image-hero'},
      extra: const MediaDetailRouteData(heroTag: 'image-hero-tag'),
    );
    await tester.pump();

    final page = detailTransitionPage(tester);
    const child = SizedBox(key: ValueKey('hero-transition-child'));
    final built = page.transitionsBuilder(
      tester.element(find.byType(MaterialApp)),
      const AlwaysStoppedAnimation(0.5),
      kAlwaysDismissedAnimation,
      child,
    );
    expect(identical(built, child), isTrue);
    await tester.pump(LumaMotion.normal);
  });

  testWidgets('reduced motion completes the detail fade immediately', (
    tester,
  ) async {
    final dependencies = createDependencies();
    dependencies.session.connect(connectedProfile());
    final router = createAppRouter(dependencies);
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      routedApp(dependencies, router, disableAnimations: true),
    );
    await tester.pump();
    router.pushNamed<void>(
      AppRoute.catalogDetail,
      pathParameters: const {'catalogId': 'catalog-transition'},
      extra: CatalogDetailRouteData(initialItem: catalogItem()),
    );
    await tester.pump();

    final page = detailTransitionPage(tester);
    expect(page.transitionDuration, Duration.zero);
    expect(page.reverseTransitionDuration, Duration.zero);
  });

  testWidgets(
    'player route uses the initial item without a blocking detail load',
    (tester) async {
      final repository = _CountingMediaRepository();
      final dependencies = createDependencies(mediaRepository: repository);
      dependencies.session.connect(connectedProfile());
      final router = createAppRouter(dependencies);
      addTearDown(router.dispose);
      addTearDown(dependencies.dispose);
      final item = buildMediaFixtures().first;

      await tester.pumpWidget(routedApp(dependencies, router));
      await tester.pump();
      router.pushNamed<void>(
        AppRoute.player,
        pathParameters: {'mediaId': item.id},
        extra: PlayerRouteData(initialItem: item),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(PlayerScene), findsOneWidget);
      expect(repository.detailCalls, 0);
      await dependencies.playerSession.close();
    },
  );

  testWidgets('player deep link loads in place and exposes a stable retry', (
    tester,
  ) async {
    final repository = _FailingDetailMediaRepository();
    final dependencies = createDependencies(mediaRepository: repository);
    dependencies.session.connect(connectedProfile());
    final router = createAppRouter(dependencies)..go('/player/missing');
    addTearDown(router.dispose);
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(routedApp(dependencies, router));
    await tester.pump();
    await tester.pump();

    expect(find.text('播放器'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(repository.detailCalls, 2);
  });

  for (final path in [
    '/settings/access',
    '/settings/access/new',
    '/settings/access/member-1',
  ]) {
    testWidgets(
      'access deep link $path rejects users without management permission',
      (tester) async {
        final dependencies = AppDependencies(
          mediaRepository: MockMediaRepository(),
          connectionService: MockConnectionService(),
          sourceRepository: _RouteSourceRepository(),
          accessRepository: _RouteAccessRepository(),
        );
        dependencies.session.connect(
          const ServerProfile(
            name: 'server.local',
            address: 'http://server.local:8080',
            token: 'token',
            hostName: 'server.local',
            userRole: 'member',
            capabilities: ['media.read'],
          ),
        );
        final router = createAppRouter(dependencies)..go(path);
        addTearDown(router.dispose);
        addTearDown(dependencies.dispose);

        await tester.pumpWidget(routedApp(dependencies, router));
        await tester.pump();

        expect(router.routeInformationProvider.value.uri.path, '/settings');
        expect(find.text('设置'), findsWidgets);
      },
    );
  }

  for (final entry in <String, String>{
    'luma://app/media/video-0': '/media/video-0',
    'luma://app/catalog/catalog-1': '/catalog/catalog-1',
    'luma://app/player/video-0': '/player/video-0',
    'luma://app/settings': '/settings',
  }.entries) {
    testWidgets('custom deep link ${entry.key} maps to ${entry.value}', (
      tester,
    ) async {
      final dependencies = createDependencies();
      dependencies.session.connect(connectedProfile());
      final router = createAppRouter(dependencies)..go(entry.key);
      addTearDown(router.dispose);
      addTearDown(dependencies.dispose);

      await tester.pumpWidget(routedApp(dependencies, router));
      await tester.pump();

      expect(router.routeInformationProvider.value.uri.path, entry.value);
      if (entry.value.startsWith('/player/')) {
        await dependencies.playerSession.close();
      }
    });
  }
}

class _CountingMediaRepository extends MockMediaRepository {
  var detailCalls = 0;

  @override
  Future<MediaItem> loadDetail(String id) {
    detailCalls++;
    return super.loadDetail(id);
  }
}

class _FailingDetailMediaRepository extends MockMediaRepository {
  var detailCalls = 0;

  @override
  Future<MediaItem> loadDetail(String id) async {
    detailCalls++;
    throw StateError('媒体读取失败');
  }
}

class _RecordingPagingMediaRepository extends MockMediaRepository {
  var searchCalls = 0;
  final limits = <int?>[];

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async {
    searchCalls++;
    limits.add(limit);
    return const MediaListPage(items: [], nextCursor: null);
  }
}

final class _RouteSourceRepository implements SourceRepository {
  @override
  Future<Source?> find(String id) async => null;

  @override
  Future<List<Source>> list({bool refresh = false}) async => const [];
}

final class _RouteAccessRepository implements AccessRepository {
  @override
  Future<AccessUser> createUser(
    String name, {
    required String username,
    required String password,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Future<void> grantSource(String userId, String sourceId) async {}

  @override
  Future<List<String>> listGrants(String userId) async => const [];

  @override
  Future<List<LoginSession>> listSessions(String userId) async => const [];

  @override
  Future<List<AccessUser>> listUsers() async => const [];

  @override
  Future<void> resetPassword(String userId, String password) async {}

  @override
  Future<void> revokeSession(String sessionId) async {}

  @override
  Future<void> revokeSource(String userId, String sourceId) async {}

  @override
  Future<AccessUser> updateUser(String id, {String? name, bool? enabled}) =>
      throw UnimplementedError();
}

class _BlockingDetailMediaRepository extends MockMediaRepository {
  final _detail = Completer<MediaItem>();
  var detailCalls = 0;

  @override
  Future<MediaItem> loadDetail(String id) {
    detailCalls++;
    return _detail.future;
  }

  void completeError(Object error) => _detail.completeError(error);
}
