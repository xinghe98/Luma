import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/api_access.dart';
import '../../data/repositories/source_repository.dart';
import '../../features/settings/access/access_management_page.dart';
import '../../features/settings/access/member_detail_page.dart';
import '../../features/settings/access/new_member_page.dart';
import '../../features/settings/library_sources_page.dart';
import '../app_dependencies.dart';
import '../app_route.dart';
import 'route_support_pages.dart';

List<RouteBase> buildSettingsRoutes(
  AppDependencies dependencies,
  GlobalKey<NavigatorState> rootNavigatorKey,
) => [
  GoRoute(
    parentNavigatorKey: rootNavigatorKey,
    name: AppRoute.librarySources,
    path: '/settings/sources',
    builder: (_, _) {
      final sources = dependencies.sources;
      if (sources is! MutableSourceRepository) {
        return const UnavailableRoutePage(
          title: '媒体源类型',
          message: '当前服务器不支持媒体源管理。',
        );
      }
      return LibrarySourcesPage(
        repository: sources,
        access: dependencies.access,
      );
    },
  ),
  GoRoute(
    parentNavigatorKey: rootNavigatorKey,
    name: AppRoute.accessManagement,
    path: '/settings/access',
    redirect: (_, _) => _guardAccessManagement(dependencies),
    builder: (_, _) {
      final sources = dependencies.sources;
      if (sources == null) {
        return const UnavailableRoutePage(
          title: '成员与访问管理',
          message: '当前服务器不支持成员与访问管理。',
        );
      }
      return AccessManagementPage(
        access: dependencies.access,
        sources: sources,
      );
    },
  ),
  GoRoute(
    parentNavigatorKey: rootNavigatorKey,
    name: AppRoute.newMember,
    path: '/settings/access/new',
    redirect: (_, _) => _guardAccessManagement(dependencies),
    builder: (_, _) {
      final sources = dependencies.sources;
      if (sources == null) {
        return const UnavailableRoutePage(
          title: '添加成员',
          message: '当前服务器不支持成员与访问管理。',
        );
      }
      return NewMemberPage(access: dependencies.access, sources: sources);
    },
  ),
  GoRoute(
    parentNavigatorKey: rootNavigatorKey,
    name: AppRoute.memberDetail,
    path: '/settings/access/:userId',
    redirect: (_, _) => _guardAccessManagement(dependencies),
    builder: (_, state) => AccessUserRoutePage(
      access: dependencies.access,
      sources: dependencies.sources,
      userId: state.pathParameters['userId']!,
      initialUser: state.extra is AccessUser ? state.extra as AccessUser : null,
      builder: (user, sources) => MemberDetailPage(
        access: dependencies.access,
        sources: sources,
        user: user,
      ),
    ),
  ),
];

/// 与设置页入口使用相同权限，阻止成员通过深链进入访问管理页面。
String? _guardAccessManagement(AppDependencies dependencies) {
  final server = dependencies.session.server;
  final allowed =
      server != null &&
      server.userRole == 'admin' &&
      server.capabilities.contains('users.manage') &&
      dependencies.sources != null;
  return allowed ? null : '/settings';
}
