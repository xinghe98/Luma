// App router composes domain route builders behind one stable application entry point.
// It owns connection redirects and the root navigator while feature route modules remain independent.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/connection/connection_page.dart';
import '../features/shell/app_destination.dart';
import 'app_dependencies.dart';
import 'app_route.dart';
import 'routes/media_routes.dart';
import 'routes/route_support_pages.dart';
import 'routes/settings_routes.dart';
import 'routes/shell_routes.dart';

export 'app_navigation.dart';
export 'app_route.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Creates the application router with stable deep links and session redirects.
GoRouter createAppRouter(AppDependencies dependencies) => GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppDestination.home.path,
  refreshListenable: dependencies.session,
  redirect: (context, state) {
    final path = state.uri.path;
    final isConnection = path == '/connect';
    if (!dependencies.session.isConnected && !isConnection) return '/connect';
    if (dependencies.session.isConnected && isConnection) {
      return AppDestination.home.path;
    }
    return null;
  },
  routes: [
    GoRoute(
      name: AppRoute.connection,
      path: '/connect',
      builder: (_, _) => const ConnectionPage(),
    ),
    buildShellRoutes(),
    ...buildMediaRoutes(dependencies, _rootNavigatorKey),
    ...buildSettingsRoutes(dependencies, _rootNavigatorKey),
  ],
  errorBuilder: (_, _) => const UnavailableRoutePage(
    title: '找不到页面',
    message: '该地址不存在，或对应内容已经不可用。',
  ),
);
