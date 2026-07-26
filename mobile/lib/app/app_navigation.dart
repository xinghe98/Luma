import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models/api_catalog.dart';
import '../data/models/media_item.dart';
import '../data/models/media_types.dart';
import '../features/details/dialogs/image_preview_dialog.dart';
import '../features/shell/app_destination.dart';
import 'app_route.dart';
import 'app_scope.dart';

/// 媒体详情路由的首帧与过渡参数，不写入持久化媒体状态。
class MediaDetailRouteData {
  const MediaDetailRouteData({
    this.initialItem,
    this.heroTag,
    this.useLightTransition = false,
  });

  final MediaItem? initialItem;
  final String? heroTag;
  final bool useLightTransition;
}

/// 作品详情路由携带来源页已有内容，并在页面过渡后刷新完整资料。
class CatalogDetailRouteData {
  /// 携带来源作品摘要与可选海报标签，不写入持久状态。
  const CatalogDetailRouteData({this.initialItem, this.heroTag});

  final CatalogItem? initialItem;
  final String? heroTag;
}

extension AppNavigation on BuildContext {
  void goToDestination(AppDestination destination) =>
      goNamed(destination.routeName);

  /// 打开媒体详情；视频使用轻量淡入，图片继续使用来源封面的 Hero。
  void openMediaDetails(MediaItem item, {String? heroTag}) {
    // MediaItem 不含作品类型等构造 CatalogItem 所需字段，先进入媒体详情，
    // 避免为了作品路由丢掉来源页已经具备的首帧内容。
    AppScope.of(this).media.remember(item, notify: false);
    final isVideo = item.type == MediaType.video;
    pushNamed<void>(
      AppRoute.mediaDetail,
      pathParameters: {'mediaId': item.id},
      extra: MediaDetailRouteData(
        initialItem: item,
        heroTag: isVideo ? null : heroTag,
        useLightTransition: isVideo,
      ),
    );
  }

  /// 打开图片预览；有来源标签时从当前缩略图原地放大并在关闭时缩回。
  Future<void> openImagePreview(MediaItem item, {String? heroTag}) async {
    AppScope.of(this).media.remember(item, notify: false);
    final action = await showImagePreviewDialog(this, item, heroTag: heroTag);
    if (!mounted || action != ImagePreviewAction.openDetails) return;
    openMediaDetails(item);
  }

  /// 打开电影或电视剧详情，首帧复用来源卡片数据，并可让海报独占路由动效。
  void openCatalogDetails(CatalogItem item, {String? heroTag}) =>
      pushNamed<void>(
        AppRoute.catalogDetail,
        pathParameters: {'catalogId': item.id},
        extra: CatalogDetailRouteData(initialItem: item, heroTag: heroTag),
      );

  /// 立即打开播放器；有来源条目时首帧直接使用，缺失时由播放器页加载。
  Future<void> openPlayer(
    String mediaId, {
    MediaItem? initialItem,
    bool startFromBeginning = false,
  }) async {
    final media = AppScope.of(this).media;
    final item = initialItem ?? media.findById(mediaId);
    if (item != null) media.remember(item, notify: false);
    await pushNamed<void>(
      AppRoute.player,
      pathParameters: {'mediaId': mediaId},
      extra: PlayerRouteData(
        initialItem: item,
        startFromBeginning: startFromBeginning,
      ),
    );
  }
}

/// PlayerRouteData 在路由层传递一次性起播意图，不写入媒体用户资料。
class PlayerRouteData {
  const PlayerRouteData({this.initialItem, this.startFromBeginning = false});

  final MediaItem? initialItem;
  final bool startFromBeginning;
}
