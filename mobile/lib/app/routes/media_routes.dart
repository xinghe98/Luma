import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../app_scope.dart';

List<RouteBase> buildMediaRoutes(
  AppDependencies dependencies,
  GlobalKey<NavigatorState> rootNavigatorKey,
) => [
  GoRoute(
    parentNavigatorKey: rootNavigatorKey,
    name: AppRoute.mediaDetail,
    path: '/media/:mediaId',
    pageBuilder: (context, state) {
      final extra = state.extra;
      final routeData = extra is MediaDetailRouteData
          ? extra
          : MediaDetailRouteData(heroTag: extra as String?);
      final child = MediaDetailPage(
        mediaId: state.pathParameters['mediaId']!,
        initialItem: routeData.initialItem,
        heroTag: routeData.heroTag,
      );
      if (routeData.heroTag != null) {
        return _heroOnlyPage(context, state.pageKey, child);
      }
      if (!routeData.useLightTransition) {
        return MaterialPage<void>(key: state.pageKey, child: child);
      }
      return _detailFadePage(context, state.pageKey, child);
    },
  ),
  GoRoute(
    parentNavigatorKey: rootNavigatorKey,
    name: AppRoute.catalogDetail,
    path: '/catalog/:catalogId',
    pageBuilder: (context, state) {
      final extra = state.extra;
      final routeData = switch (extra) {
        CatalogDetailRouteData data => data,
        CatalogItem item => CatalogDetailRouteData(initialItem: item),
        _ => const CatalogDetailRouteData(),
      };
      final child = CatalogDetailPage(
        catalogId: state.pathParameters['catalogId']!,
        initialItem: routeData.initialItem,
        heroTag: routeData.heroTag,
        repository: dependencies.catalog,
        onOpenMedia: context.openPlayer,
        onOpenMediaFromStart: (mediaId) =>
            context.openPlayer(mediaId, startFromBeginning: true),
        onWarmStream: dependencies.media.warmStream,
      );
      return routeData.heroTag == null
          ? _detailFadePage(context, state.pageKey, child)
          : _heroOnlyPage(context, state.pageKey, child);
    },
  ),
  GoRoute(
    parentNavigatorKey: rootNavigatorKey,
    name: AppRoute.movieCollection,
    path: '/videos/movies',
    pageBuilder: (context, state) => _collectionPage(
      context,
      state.pageKey,
      CatalogCollectionPage(
        kind: CatalogKind.movie,
        initialItems: state.extra is List<CatalogItem>
            ? state.extra as List<CatalogItem>
            : const [],
        onOpenCatalog: (item, {heroTag}) =>
            context.openCatalogDetails(item, heroTag: heroTag),
        onOpenSearch: () => context.goToDestination(AppDestination.search),
      ),
    ),
  ),
  GoRoute(
    parentNavigatorKey: rootNavigatorKey,
    name: AppRoute.seriesCollection,
    path: '/videos/series',
    pageBuilder: (context, state) => _collectionPage(
      context,
      state.pageKey,
      CatalogCollectionPage(
        kind: CatalogKind.series,
        initialItems: state.extra is List<CatalogItem>
            ? state.extra as List<CatalogItem>
            : const [],
        onOpenCatalog: (item, {heroTag}) =>
            context.openCatalogDetails(item, heroTag: heroTag),
        onOpenSearch: () => context.goToDestination(AppDestination.search),
      ),
    ),
  ),
  GoRoute(
    parentNavigatorKey: rootNavigatorKey,
    name: AppRoute.personalVideos,
    path: '/videos/personal',
    pageBuilder: (context, state) => _collectionPage(
      context,
      state.pageKey,
      LibraryPage(
        type: MediaType.video,
        fixedLibraryKind: 'personal',
        title: '个人视频',
        pageSize: 18,
        initialItems: state.extra is List<MediaItem>
            ? state.extra as List<MediaItem>
            : const [],
        onOpenMedia: (item, {heroTag}) =>
            context.openMediaDetails(item, heroTag: heroTag),
        onOpenSearch: () => context.goToDestination(AppDestination.search),
      ),
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
        initialItem: routeData.initialItem,
        startFromBeginning: routeData.startFromBeginning,
      );
    },
  ),
];

/// Hero 独占图片或作品海报的位移动画，页面本身不再叠加平台过渡。
CustomTransitionPage<void> _heroOnlyPage(
  BuildContext context,
  LocalKey key,
  Widget child,
) {
  final duration = LumaMotion.forContext(context, LumaMotion.normal);
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: (_, _, _, child) => child,
    child: child,
  );
}

CustomTransitionPage<void> _detailFadePage(
  BuildContext context,
  LocalKey key,
  Widget child,
) {
  final duration = LumaMotion.forContext(context, LumaMotion.normal);
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: _detailFade,
    child: child,
  );
}

CustomTransitionPage<void> _collectionPage(
  BuildContext context,
  LocalKey key,
  Widget child,
) {
  final duration = LumaMotion.forContext(context, LumaMotion.normal);
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: _collectionReveal,
    child: AppScope.of(context).deviceProfile.isTelevision
        ? _TvCollectionFocusEntry(child: child)
        : child,
  );
}

/// 根层集合页持有独立焦点历史；首入场与控件卸载后的空焦点只在当前路由恢复。
/// 详情或弹窗覆盖期间不请求焦点，返回后由 scope 保留原来的卡片位置。
class _TvCollectionFocusEntry extends StatefulWidget {
  const _TvCollectionFocusEntry({required this.child});

  final Widget child;

  @override
  State<_TvCollectionFocusEntry> createState() =>
      _TvCollectionFocusEntryState();
}

class _TvCollectionFocusEntryState extends State<_TvCollectionFocusEntry> {
  final _scope = FocusScopeNode(debugLabel: 'tv-collection');
  bool _focusScheduled = false;

  @override
  void initState() {
    super.initState();
    _scope.addListener(_restoreUnclaimedFocus);
  }

  void _restoreUnclaimedFocus() {
    if (!_scope.hasPrimaryFocus || _focusScheduled) return;
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScheduled = false;
      if (!mounted ||
          !_scope.hasPrimaryFocus ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      // 优先进入纵向内容中的卡片或重试按钮，横向筛选栏不占用首焦点。
      for (final node in _scope.traversalDescendants) {
        final nodeContext = node.context;
        if (nodeContext != null &&
            Scrollable.maybeOf(nodeContext, axis: Axis.vertical) != null) {
          node.requestFocus();
          return;
        }
      }
      _scope.nextFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape &&
        event.logicalKey != LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (context.canPop()) {
        unawaited(Navigator.of(context).maybePop());
      } else {
        context.goToDestination(AppDestination.videos);
      }
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _scope
      ..removeListener(_restoreUnclaimedFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: context.canPop(),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) context.goToDestination(AppDestination.videos);
    },
    child: FocusScope(
      node: _scope,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: widget.child,
    ),
  );
}

Widget _collectionReveal(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutQuart,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.04, 0),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    ),
  );
}

Widget _detailFade(
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
