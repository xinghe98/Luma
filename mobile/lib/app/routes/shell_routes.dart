import 'package:go_router/go_router.dart';

import '../../data/models/media_types.dart';
import '../../features/catalog/catalog_page.dart';
import '../../features/home/home_page.dart';
import '../../features/library/library_page.dart';
import '../../features/search/search_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/shell/app_destination.dart';
import '../../features/shell/app_shell.dart';
import '../app_navigation.dart';
import '../app_route.dart';

StatefulShellRoute buildShellRoutes() => StatefulShellRoute.indexedStack(
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
            onOpenSearch: () => context.goToDestination(AppDestination.search),
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
            onOpenSearch: () => context.goToDestination(AppDestination.search),
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
            onOpenCatalog: (item, {heroTag}) =>
                context.openCatalogDetails(item, heroTag: heroTag),
            onOpenPersonalMedia: (item, {heroTag}) =>
                context.openMediaDetails(item, heroTag: heroTag),
            onOpenSearch: () => context.goToDestination(AppDestination.search),
            onOpenMovies: (items) =>
                context.pushNamed(AppRoute.movieCollection, extra: items),
            onOpenSeries: (items) =>
                context.pushNamed(AppRoute.seriesCollection, extra: items),
            onOpenPersonalVideos: (items) =>
                context.pushNamed(AppRoute.personalVideos, extra: items),
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
);
