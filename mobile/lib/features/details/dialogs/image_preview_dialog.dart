import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/route_transition.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/media/authenticated_media_image.dart';

/// 图片预览关闭后交还给调用方的后续动作。
enum ImagePreviewAction { openDetails }

/// 打开不透明的全屏图片预览，支持缩放、还原和进入详情。
/// 有 [heroTag] 时从来源缩略图原地放大；无来源时退化为短淡入。
Future<ImagePreviewAction?> showImagePreviewDialog(
  BuildContext context,
  MediaItem item, {
  String? heroTag,
}) async {
  final route = PageRouteBuilder<ImagePreviewAction>(
    opaque: true,
    settings: const RouteSettings(name: 'image-preview'),
    transitionsBuilder: (_, _, _, child) => child,
    transitionDuration: LumaMotion.forContext(context, LumaMotion.slow),
    reverseTransitionDuration: LumaMotion.forContext(context, LumaMotion.slow),
    pageBuilder: (context, animation, secondaryAnimation) {
      return ImagePreviewDialog(item: item, heroTag: heroTag);
    },
  );
  final result = await Navigator.of(
    context,
    rootNavigator: true,
  ).push<ImagePreviewAction>(route);
  final animation = route.animation;
  if (animation != null && animation.status != AnimationStatus.dismissed) {
    final completer = Completer<void>();
    void waitForDismissed(AnimationStatus status) {
      if (status == AnimationStatus.dismissed && !completer.isCompleted) {
        completer.complete();
      }
    }

    animation.addStatusListener(waitForDismissed);
    waitForDismissed(animation.status);
    await completer.future;
    animation.removeStatusListener(waitForDismissed);
  }
  await WidgetsBinding.instance.endOfFrame;
  return result;
}

class ImagePreviewDialog extends StatefulWidget {
  /// 构建全屏图片预览；[heroTag] 为空时使用无共享元素的降级动效。
  const ImagePreviewDialog({super.key, required this.item, this.heroTag});

  final MediaItem item;
  final String? heroTag;

  @override
  State<ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<ImagePreviewDialog> {
  final _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _originalLoadAllowed = false;
  bool _transitionWaitStarted = false;
  bool _closing = false;

  static const _minScale = 1.0;
  static const _maxScale = 4.0;
  static const _doubleTapScale = 2.5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_transitionWaitStarted) return;
    _transitionWaitStarted = true;
    _allowOriginalLoadAfterTransition();
  }

  /// Hero 与页面动画完成后才允许请求原图，确保飞行始终复用来源缩略图。
  Future<void> _allowOriginalLoadAfterTransition() async {
    await waitForRouteTransition(context);
    if (mounted) setState(() => _originalLoadAllowed = true);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;
    final current = _transform.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      _transform.value = Matrix4.identity();
      return;
    }
    final x = -position.dx * (_doubleTapScale - 1);
    final y = -position.dy * (_doubleTapScale - 1);
    _transform.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
  }

  /// 先还原缩放并隐藏原图，再触发反向 Hero，确保图片准确缩回来源卡片。
  Future<void> _close([ImagePreviewAction? action]) async {
    if (_closing) return;
    setState(() => _closing = true);
    _transform.value = Matrix4.identity();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, action);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final top = MediaQuery.paddingOf(context).top;
    final routeAnimation = ModalRoute.of(context)?.animation;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final size = MediaQuery.sizeOf(context);
    // 预览按屏幕 2x 解码并限制在约 6MP；若两边都单独钳到 4096，
    // 竖图/横图会接近 16MP，容易在部分设备上造成内存尖峰。
    final ratio = item.aspectRatio.isFinite && item.aspectRatio > 0
        ? item.aspectRatio.clamp(0.1, 10.0)
        : 1.0;
    final logicalWidth = size.width * dpr * 2;
    final logicalHeight = size.height * dpr * 2;
    var targetWidth = ratio >= 1 ? logicalWidth : logicalHeight * ratio;
    var targetHeight = ratio >= 1 ? logicalWidth / ratio : logicalHeight;
    final pixelScale = math.min(
      1.0,
      math.sqrt(6000000 / (targetWidth * targetHeight)),
    );
    final edgeScale = math.min(
      1.0,
      4096 / math.max(targetWidth * pixelScale, targetHeight * pixelScale),
    );
    targetWidth *= pixelScale * edgeScale;
    targetHeight *= pixelScale * edgeScale;
    final cacheWidth = targetWidth.round().clamp(1, 4096).toInt();
    final cacheHeight = targetHeight.round().clamp(1, 4096).toInt();
    final thumbCacheWidth = (size.width * dpr).round().clamp(1, 1280).toInt();
    final thumbCacheHeight = (size.height * dpr).round().clamp(1, 1280).toInt();
    final displaySize = _containedSize(size, ratio);

    final originalPath =
        (item.originalUrl != null && item.originalUrl!.isNotEmpty)
        ? item.originalUrl!
        : item.thumbnailUrl;
    final thumbPath = item.thumbnailUrl;
    // 缩略图始终垫底并参与 Hero，原图只在转场完成后叠加，退出前先移除。
    final thumbnail = Material(
      type: MaterialType.transparency,
      child: thumbPath.isEmpty
          ? const SizedBox.expand()
          : AuthenticatedMediaImage(
              path: thumbPath,
              fit: BoxFit.contain,
              cacheWidth: thumbCacheWidth,
              cacheHeight: thumbCacheHeight,
              resizePolicy: ResizeImagePolicy.fit,
              fallback: const SizedBox.expand(),
            ),
    );
    final heroThumbnail = widget.heroTag == null
        ? thumbnail
        : Hero(
            tag: widget.heroTag!,
            createRectTween: _straightRectTween,
            flightShuttleBuilder: _thumbnailFlightShuttle,
            child: thumbnail,
          );
    final image = SizedBox(
      width: displaySize.width,
      height: displaySize.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          heroThumbnail,
          if (_originalLoadAllowed && !_closing && originalPath.isNotEmpty)
            AuthenticatedMediaImage(
              path: originalPath,
              fit: BoxFit.contain,
              fullResolution: true,
              cacheWidth: cacheWidth,
              cacheHeight: cacheHeight,
              fadeInDuration: LumaMotion.forContext(context, LumaMotion.normal),
              resizePolicy: ResizeImagePolicy.fit,
              fallback: const SizedBox.expand(),
            ),
        ],
      ),
    );

    final preview = widget.heroTag == null && routeAnimation != null
        ? FadeTransition(
            opacity: CurvedAnimation(
              parent: routeAnimation,
              curve: Curves.easeOutQuart,
              reverseCurve: Curves.easeInCubic,
            ),
            child: image,
          )
        : image;

    final chromeWidget = _PreviewChrome(
      onDetails: () => unawaited(_close(ImagePreviewAction.openDetails)),
      onClose: () => unawaited(_close()),
    );
    final chromeContent = routeAnimation == null
        ? chromeWidget
        : FadeTransition(
            opacity: CurvedAnimation(
              parent: routeAnimation,
              curve: const Interval(0.45, 1, curve: Curves.easeOut),
              reverseCurve: const Interval(0, 0.55, curve: Curves.easeIn),
            ),
            child: chromeWidget,
          );
    final chrome = Positioned(
      top: top + LumaSpacing.xs,
      left: LumaSpacing.xs,
      right: LumaSpacing.xs,
      child: chromeContent,
    );

    final backdrop = ColoredBox(color: context.luma.playerInk);
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_closing) unawaited(_close());
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (routeAnimation == null)
                backdrop
              else
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: routeAnimation,
                    curve: Curves.easeOutQuart,
                    reverseCurve: Curves.easeInCubic,
                  ),
                  child: backdrop,
                ),
              Semantics(
                image: true,
                label: '图片预览：${item.title}',
                hint: '可双指缩放或双击放大',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTapDown: (details) => _doubleTapDetails = details,
                  onDoubleTap: _onDoubleTap,
                  child: Center(
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: _minScale,
                      maxScale: _maxScale,
                      clipBehavior: Clip.none,
                      child: preview,
                    ),
                  ),
                ),
              ),
              chrome,
            ],
          ),
        ),
      ),
    );
  }
}

Size _containedSize(Size viewport, double aspectRatio) {
  final viewportRatio = viewport.width / viewport.height;
  if (viewportRatio > aspectRatio) {
    return Size(viewport.height * aspectRatio, viewport.height);
  }
  return Size(viewport.width, viewport.width / aspectRatio);
}

RectTween _straightRectTween(Rect? begin, Rect? end) =>
    RectTween(begin: begin, end: end);

Widget _thumbnailFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  // 正向保留来源缩略图，反向直接使用目标卡片，避免把已缩放的原图带回列表。
  final endpoint = direction == HeroFlightDirection.push
      ? fromHeroContext.widget as Hero
      : toHeroContext.widget as Hero;
  return endpoint.child;
}

class _PreviewChrome extends StatelessWidget {
  const _PreviewChrome({required this.onDetails, required this.onClose});

  final VoidCallback onDetails;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    final chromeStyle = IconButton.styleFrom(
      backgroundColor: extras.badgeScrim,
      foregroundColor: extras.onPlayerInk,
    );
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: '详情',
          style: chromeStyle,
          onPressed: onDetails,
          icon: const Icon(Icons.info_outline_rounded),
        ),
        const Spacer(),
        IconButton.filledTonal(
          tooltip: '关闭',
          style: chromeStyle,
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}
