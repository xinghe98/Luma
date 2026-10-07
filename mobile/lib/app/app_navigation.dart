import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    // TV 不使用 Hero：根层路由统一单一短淡入，焦点由列表恢复。
    final isTelevision = AppScope.of(this).deviceProfile.isTelevision;
    pushNamed<void>(
      AppRoute.mediaDetail,
      pathParameters: {'mediaId': item.id},
      extra: MediaDetailRouteData(
        initialItem: item,
        heroTag: isTelevision ? null : (isVideo ? null : heroTag),
        useLightTransition: isVideo || isTelevision,
      ),
    );
  }

  /// 打开图片预览；有来源标签时从当前缩略图原地放大并在关闭时缩回。
  Future<void> openImagePreview(MediaItem item, {String? heroTag}) async {
    AppScope.of(this).media.remember(item, notify: false);
    // TV 预览不走 Hero，退化为短淡入并保留转场等待逻辑。
    final isTelevision = AppScope.of(this).deviceProfile.isTelevision;
    final action = await showImagePreviewDialog(
      this,
      item,
      heroTag: isTelevision ? null : heroTag,
    );
    if (!mounted || action != ImagePreviewAction.openDetails) return;
    openMediaDetails(item);
  }

  /// 打开电影或电视剧详情，首帧复用来源卡片数据，并可让海报独占路由动效。
  void openCatalogDetails(CatalogItem item, {String? heroTag}) {
    final isTelevision = AppScope.of(this).deviceProfile.isTelevision;
    pushNamed<void>(
      AppRoute.catalogDetail,
      pathParameters: {'catalogId': item.id},
      extra: CatalogDetailRouteData(
        initialItem: item,
        heroTag: isTelevision ? null : heroTag,
      ),
    );
  }

  /// 立即打开播放器，并在推送路由前异步触发流预热。
  Future<void> openPlayer(
    String mediaId, {
    MediaItem? initialItem,
    bool startFromBeginning = false,
  }) async {
    final media = AppScope.of(this).media;
    final item = initialItem ?? media.findById(mediaId);
    if (item != null) media.remember(item, notify: false);
    unawaited(media.warmStream(mediaId));
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

/// 详情页统一处理按钮、系统与键盘返回；保留来源路由及其焦点、滚动状态。
/// 有来源时允许框架正常出栈，只有独立深链才回首页；离场期间忽略重复请求。
class DetailBackScope extends StatefulWidget {
  /// 构造详情返回边界；页面离场前只接受一次按钮或键盘返回请求。
  const DetailBackScope({super.key, required this.builder});

  /// 使用同一返回回调构造详情内容，加载与错误状态也应显示返回入口。
  final Widget Function(VoidCallback onBack) builder;

  @override
  State<DetailBackScope> createState() => _DetailBackScopeState();
}

class _DetailBackScopeState extends State<DetailBackScope> {
  bool _leaving = false;

  void _back() {
    if (_leaving || ModalRoute.of(context)?.isCurrent == false) return;
    final router = GoRouter.maybeOf(context);
    final navigator = Navigator.of(context);
    if (router?.canPop() ?? navigator.canPop()) {
      _leaving = true;
      if (router != null) {
        router.pop();
      } else {
        navigator.pop();
      }
    } else if (router != null) {
      _leaving = true;
      router.go(
        AppDestination.landingPath(
          television: AppScope.of(context).deviceProfile.isTelevision,
        ),
      );
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isBack =
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        (key == LogicalKeyboardKey.arrowLeft &&
            HardwareKeyboard.instance.isAltPressed);
    if (!isBack) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _back();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: ModalRoute.canPopOf(context) ?? false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) {
        _leaving = true;
      } else {
        _back();
      }
    },
    // 作用域接收加载期按键，并把有效内容的首焦点留给播放或收藏按钮。
    child: FocusScope(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: widget.builder(_back),
    ),
  );
}
