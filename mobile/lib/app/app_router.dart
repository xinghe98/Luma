import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../data/models/api_access.dart';
import '../data/models/api_catalog.dart';
import '../data/models/media_item.dart';
import '../data/models/media_types.dart';
import '../data/repositories/access_repository.dart';
import '../data/repositories/source_repository.dart';
import '../features/catalog/catalog_detail_page.dart';
import '../features/catalog/catalog_page.dart';
import '../features/connection/connection_page.dart';
import '../features/details/dialogs/image_preview_dialog.dart';
import '../features/details/media_detail_page.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/player/player_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/access/access_management_page.dart';
import '../features/settings/access/issue_token_page.dart';
import '../features/settings/access/member_detail_page.dart';
import '../features/settings/access/new_member_page.dart';
import '../features/settings/library_sources_page.dart';
import '../features/settings/organization_page.dart';
import '../features/settings/settings_page.dart';
import '../features/shell/app_destination.dart';
import '../features/shell/app_shell.dart';
import '../shared/states/empty_state.dart';
import '../shared/states/skeleton.dart';
import 'app_dependencies.dart';
import 'app_scope.dart';

abstract final class AppRoute {
  static const connection = 'connection';
  static const mediaDetail = 'media-detail';
  static const catalogDetail = 'catalog-detail';
  static const movieCollection = 'movie-collection';
  static const seriesCollection = 'series-collection';
  static const personalVideos = 'personal-videos';
  static const player = 'player';
  static const librarySources = 'library-sources';
  static const organization = 'organization';
  static const organizationEditor = 'organization-editor';
  static const accessManagement = 'access-management';
  static const newMember = 'new-member';
  static const memberDetail = 'member-detail';
  static const issueToken = 'issue-token';
}

/// Route-only presentation data for media details.
///
/// Videos skip Hero and use a short fade because their cover must not compete
/// with the platform route transition for raster work.
class _MediaDetailRouteData {
  const _MediaDetailRouteData({
    this.heroTag,
    this.useLightTransition = false,
    this.initialLoadDelay = Duration.zero,
  });

  final String? heroTag;
  final bool useLightTransition;
  final Duration initialLoadDelay;
}

/// Applies a lightweight opacity-only transition without moving or scaling UI.
Widget _lightFade(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) => FadeTransition(
  opacity: CurvedAnimation(
    parent: animation,
    curve: LumaMotion.standard,
    reverseCurve: Curves.easeInCubic,
  ),
  child: child,
);

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

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
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              name: AppDestination.home.routeName,
              path: AppDestination.home.path,
              builder: (context, _) => HomePage(
                onOpenMedia: (item, {heroTag}) =>
                    context.openMediaDetails(item, heroTag: heroTag),
                onOpenSearch: () =>
                    context.goToDestination(AppDestination.search),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              name: AppDestination.photos.routeName,
              path: AppDestination.photos.path,
              builder: (context, _) => LibraryPage(
                type: MediaType.image,
                onOpenMedia: (item, {heroTag}) =>
                    context.openImagePreview(item, heroTag: heroTag),
                onLongPressMedia: (item, {heroTag}) =>
                    context.openMediaDetails(item, heroTag: heroTag),
                onOpenSearch: () =>
                    context.goToDestination(AppDestination.search),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              name: AppDestination.videos.routeName,
              path: AppDestination.videos.path,
              builder: (context, _) => CatalogPage(
                onOpenCatalog: context.openCatalogDetails,
                onOpenPersonalMedia: (item, {heroTag}) =>
                    context.openMediaDetails(item, heroTag: heroTag),
                onOpenSearch: () =>
                    context.goToDestination(AppDestination.search),
                onOpenMovies: (items) => context.pushNamed(
                  AppRoute.movieCollection,
                  extra: items,
                ),
                onOpenSeries: (items) => context.pushNamed(
                  AppRoute.seriesCollection,
                  extra: items,
                ),
                onOpenPersonalVideos: (items) => context.pushNamed(
                  AppRoute.personalVideos,
                  extra: items,
                ),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              name: AppDestination.search.routeName,
              path: AppDestination.search.path,
              builder: (context, _) => SearchPage(
                onOpenMedia: (item, {heroTag}) =>
                    context.openMediaDetails(item, heroTag: heroTag),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              name: AppDestination.settings.routeName,
              path: AppDestination.settings.path,
              builder: (_, _) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.mediaDetail,
      path: '/media/:mediaId',
      pageBuilder: (_, state) {
        final extra = state.extra;
        final routeData = extra is _MediaDetailRouteData
            ? extra
            : _MediaDetailRouteData(heroTag: extra as String?);
        final child = MediaDetailPage(
          mediaId: state.pathParameters['mediaId']!,
          heroTag: routeData.heroTag,
          initialLoadDelay: routeData.initialLoadDelay,
        );
        if (!routeData.useLightTransition) {
          return MaterialPage<void>(key: state.pageKey, child: child);
        }
        return CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: LumaMotion.fast,
          reverseTransitionDuration: LumaMotion.fast,
          transitionsBuilder: _lightFade,
          child: child,
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.catalogDetail,
      path: '/catalog/:catalogId',
      pageBuilder: (context, state) => NoTransitionPage<void>(
        key: state.pageKey,
        child: CatalogDetailPage(
          catalogId: state.pathParameters['catalogId']!,
          initialItem: state.extra is CatalogItem
              ? state.extra as CatalogItem
              : null,
          repository: dependencies.catalog,
          onOpenMedia: context.openPlayer,
        ),
      ),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.movieCollection,
      path: '/videos/movies',
      builder: (context, state) => CatalogCollectionPage(
        kind: CatalogKind.movie,
        initialItems: state.extra is List<CatalogItem>
            ? state.extra as List<CatalogItem>
            : const [],
        onOpenCatalog: context.openCatalogDetails,
        onOpenSearch: () => context.goToDestination(AppDestination.search),
      ),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.seriesCollection,
      path: '/videos/series',
      builder: (context, state) => CatalogCollectionPage(
        kind: CatalogKind.series,
        initialItems: state.extra is List<CatalogItem>
            ? state.extra as List<CatalogItem>
            : const [],
        onOpenCatalog: context.openCatalogDetails,
        onOpenSearch: () => context.goToDestination(AppDestination.search),
      ),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.personalVideos,
      path: '/videos/personal',
      builder: (context, state) => LibraryPage(
        type: MediaType.video,
        fixedLibraryKind: 'personal',
        title: '个人视频',
        initialItems: state.extra is List<MediaItem>
            ? state.extra as List<MediaItem>
            : const [],
        onOpenMedia: (item, {heroTag}) =>
            context.openMediaDetails(item, heroTag: heroTag),
        onOpenSearch: () => context.goToDestination(AppDestination.search),
      ),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.player,
      path: '/player/:mediaId',
      builder: (_, state) =>
          PlayerPage(mediaId: state.pathParameters['mediaId']!),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.librarySources,
      path: '/settings/sources',
      builder: (_, _) {
        final sources = dependencies.sources;
        if (sources is! MutableSourceRepository) {
          return const _UnavailableRoutePage(
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
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.organization,
      path: '/settings/organization',
      builder: (_, _) => OrganizationPage(repository: dependencies.catalog),
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
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
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.accessManagement,
      path: '/settings/access',
      builder: (_, _) {
        final sources = dependencies.sources;
        if (sources == null) {
          return const _UnavailableRoutePage(
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
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.newMember,
      path: '/settings/access/new',
      builder: (_, _) {
        final sources = dependencies.sources;
        if (sources == null) {
          return const _UnavailableRoutePage(
            title: '添加成员',
            message: '当前服务器不支持成员与访问管理。',
          );
        }
        return NewMemberPage(access: dependencies.access, sources: sources);
      },
    ),
    GoRoute(
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.memberDetail,
      path: '/settings/access/:userId',
      builder: (_, state) => _AccessUserRoutePage(
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
      parentNavigatorKey: _rootNavigatorKey,
      name: AppRoute.issueToken,
      path: '/settings/access/:userId/token',
      builder: (_, state) => _AccessUserRoutePage(
        access: dependencies.access,
        sources: dependencies.sources,
        userId: state.pathParameters['userId']!,
        initialUser: state.extra is AccessUser ? state.extra as AccessUser : null,
        builder: (user, _) =>
            IssueTokenPage(access: dependencies.access, user: user),
      ),
    ),
  ],
  errorBuilder: (_, state) =>
      _UnavailableRoutePage(title: '找不到页面', message: '该地址不存在，或对应内容已经不可用。'),
);

extension AppNavigation on BuildContext {
  void goToDestination(AppDestination destination) =>
      goNamed(destination.routeName);

  /// Opens a media detail route with the animation appropriate to its type.
  void openMediaDetails(MediaItem item, {String? heroTag}) {
    // 搜索/库页条目不一定位于首页集合，先写入缓存再打开稳定 URL。
    AppScope.of(this).media.remember(item);
    final isVideo = item.type == MediaType.video;
    pushNamed<void>(
      AppRoute.mediaDetail,
      pathParameters: {'mediaId': item.id},
      extra: _MediaDetailRouteData(
        heroTag: isVideo ? null : heroTag,
        useLightTransition: isVideo,
        initialLoadDelay: isVideo
            ? LumaMotion.fast
            : heroTag == null
            ? Duration.zero
            : LumaMotion.slow,
      ),
    );
  }

  void openImagePreview(MediaItem item, {String? heroTag}) {
    AppScope.of(this).media.remember(item);
    showImagePreviewDialog(
      this,
      item,
      heroTag: heroTag,
      onOpenDetails: () => openMediaDetails(item, heroTag: heroTag),
    );
  }

  void openCatalogDetails(CatalogItem item) => pushNamed<void>(
    AppRoute.catalogDetail,
    pathParameters: {'catalogId': item.id},
    extra: item,
  );

  Future<void> openPlayer(String mediaId) async {
    final media = AppScope.of(this).media;
    await media.loadDetail(mediaId);
    if (!mounted || media.findById(mediaId) == null) return;
    await pushNamed<void>(
      AppRoute.player,
      pathParameters: {'mediaId': mediaId},
    );
  }
}

class _UnavailableRoutePage extends StatelessWidget {
  const _UnavailableRoutePage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: EmptyState(
      icon: Icons.link_off_rounded,
      title: title,
      message: message,
      action: FilledButton(
        onPressed: () => context.go(AppDestination.settings.path),
        child: const Text('返回设置'),
      ),
    ),
  );
}

class _AccessUserRoutePage extends StatefulWidget {
  const _AccessUserRoutePage({
    required this.access,
    required this.sources,
    required this.userId,
    this.initialUser,
    required this.builder,
  });

  final AccessRepository access;
  final SourceRepository? sources;
  final String userId;
  final AccessUser? initialUser;
  final Widget Function(AccessUser user, SourceRepository sources) builder;

  @override
  State<_AccessUserRoutePage> createState() => _AccessUserRoutePageState();
}

class _AccessUserRoutePageState extends State<_AccessUserRoutePage> {
  Future<AccessUser?>? _request;

  @override
  void initState() {
    super.initState();
    _request = widget.initialUser == null ? _load() : null;
  }

  Future<AccessUser?> _load() async {
    final users = await widget.access.listUsers();
    for (final user in users) {
      if (user.id == widget.userId) return user;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.sources;
    if (sources == null) {
      return const _UnavailableRoutePage(
        title: '成员与访问管理',
        message: '当前服务器不支持成员与访问管理。',
      );
    }
    final initialUser = widget.initialUser;
    if (initialUser != null) return widget.builder(initialUser, sources);
    return FutureBuilder<AccessUser?>(
      future: _request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: SettingsListSkeleton(items: 3),
          );
        }
        if (snapshot.hasError) {
          return _UnavailableRoutePage(
            title: '无法读取成员资料',
            message: '请检查服务器连接后重试。',
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const _UnavailableRoutePage(
            title: '找不到成员',
            message: '该成员可能已被删除，或当前账号没有访问权限。',
          );
        }
        return widget.builder(user, sources);
      },
    );
  }
}
