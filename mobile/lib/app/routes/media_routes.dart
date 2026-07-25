import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models/api_catalog.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import '../../features/catalog/catalog_detail_page.dart';
import '../../features/catalog/catalog_page.dart';
import '../../features/details/media_detail_page.dart';
import '../../features/library/library_page.dart';
import '../../features/player/player_page.dart';
import '../../features/shell/app_destination.dart';
import '../app_dependencies.dart';
import '../app_navigation.dart';
import '../app_route.dart';

List<RouteBase> buildMediaRoutes(
  AppDependencies dependencies,
  GlobalKey<NavigatorState> rootNavigatorKey,
) => [
GoRoute(
  parentNavigatorKey: rootNavigatorKey,
  name: AppRoute.mediaDetail,
  path: '/media/:mediaId',
  pageBuilder: (_, state) {
    final extra = state.extra;
    final routeData = extra is MediaDetailRouteData
        ? extra
        : MediaDetailRouteData(heroTag: extra as String?);
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
  parentNavigatorKey: rootNavigatorKey,
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
      onOpenMediaFromStart: (mediaId) => context.openPlayer(
        mediaId,
        startFromBeginning: true,
      ),
    ),
  ),
),
GoRoute(
  parentNavigatorKey: rootNavigatorKey,
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
  parentNavigatorKey: rootNavigatorKey,
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
  parentNavigatorKey: rootNavigatorKey,
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
  parentNavigatorKey: rootNavigatorKey,
  name: AppRoute.player,
  path: '/player/:mediaId',
  builder: (_, state) {
    final routeData = state.extra is PlayerRouteData
        ? state.extra as PlayerRouteData
        : const PlayerRouteData();
    return PlayerPage(
      mediaId: state.pathParameters['mediaId']!,
      startFromBeginning: routeData.startFromBeginning,
    );
  },
)
];

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
