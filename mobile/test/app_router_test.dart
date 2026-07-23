import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_router.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/server_profile.dart';

void main() {
  AppDependencies createDependencies() => AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: MockConnectionService(),
  );

  Widget routedApp(AppDependencies dependencies, GoRouter router) => AppScope(
    dependencies: dependencies,
    child: MaterialApp.router(routerConfig: router),
  );

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
}
