// Settings route construction resolves optional source and access capabilities before showing pages.
// It keeps deep-link member routes layout-stable through AccessUserRoutePage.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/api_access.dart';
import '../../data/models/api_catalog.dart';
import '../../data/repositories/source_repository.dart';
import '../../features/settings/access/access_management_page.dart';
import '../../features/settings/access/issue_token_page.dart';
import '../../features/settings/access/member_detail_page.dart';
import '../../features/settings/access/new_member_page.dart';
import '../../features/settings/library_sources_page.dart';
import '../../features/settings/organization_page.dart';
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
  name: AppRoute.organization,
  path: '/settings/organization',
  builder: (_, _) => OrganizationPage(repository: dependencies.catalog),
),
GoRoute(
  parentNavigatorKey: rootNavigatorKey,
  name: AppRoute.organizationEditor,
  path: '/settings/organization/:mediaId',
  builder: (_, state) => OrganizationMatchRoutePage(
    repository: dependencies.catalog,
    mediaId: state.pathParameters['mediaId']!,
    initialIssue: state.extra is CatalogIssue
        ? state.extra as CatalogIssue
        : null,
  ),
),
GoRoute(
  parentNavigatorKey: rootNavigatorKey,
  name: AppRoute.accessManagement,
  path: '/settings/access',
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
GoRoute(
  parentNavigatorKey: rootNavigatorKey,
  name: AppRoute.issueToken,
  path: '/settings/access/:userId/token',
  builder: (_, state) => AccessUserRoutePage(
    access: dependencies.access,
    sources: dependencies.sources,
    userId: state.pathParameters['userId']!,
    initialUser: state.extra is AccessUser ? state.extra as AccessUser : null,
    builder: (user, _) =>
        IssueTokenPage(access: dependencies.access, user: user),
  ),
)
];
