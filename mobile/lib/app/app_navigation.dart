import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../data/models/api_catalog.dart';
import '../data/models/media_item.dart';
import '../data/models/media_types.dart';
import '../features/details/dialogs/image_preview_dialog.dart';
import '../features/shell/app_destination.dart';
import 'app_route.dart';
import 'app_scope.dart';

class MediaDetailRouteData {
  const MediaDetailRouteData({
    this.heroTag,
    this.useLightTransition = false,
    this.initialLoadDelay = Duration.zero,
  });

  final String? heroTag;
  final bool useLightTransition;
  final Duration initialLoadDelay;
}

extension AppNavigation on BuildContext {
  void goToDestination(AppDestination destination) =>
      goNamed(destination.routeName);

  void openMediaDetails(MediaItem item, {String? heroTag}) {
    final catalogItemId = item.catalogItemId;
    if (catalogItemId != null && catalogItemId.isNotEmpty) {
      pushNamed<void>(
        AppRoute.catalogDetail,
        pathParameters: {'catalogId': catalogItemId},
      );
      return;
    }
    // 搜索/库页条目不一定位于首页集合，先写入缓存再打开稳定 URL。
    AppScope.of(this).media.remember(item);
    final isVideo = item.type == MediaType.video;
    pushNamed<void>(
      AppRoute.mediaDetail,
      pathParameters: {'mediaId': item.id},
      extra: MediaDetailRouteData(
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

  /// 打开播放器；从头播放时跳过已保存的本地续播位置。
  Future<void> openPlayer(
    String mediaId, {
    bool startFromBeginning = false,
  }) async {
    final media = AppScope.of(this).media;
    await media.loadDetail(mediaId);
    if (!mounted || media.findById(mediaId) == null) return;
    await pushNamed<void>(
      AppRoute.player,
      pathParameters: {'mediaId': mediaId},
      extra: PlayerRouteData(startFromBeginning: startFromBeginning),
    );
  }
}

/// PlayerRouteData 在路由层传递一次性起播意图，不写入媒体用户资料。
class PlayerRouteData {
  const PlayerRouteData({this.startFromBeginning = false});

  final bool startFromBeginning;
}
