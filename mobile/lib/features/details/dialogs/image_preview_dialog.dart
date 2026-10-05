import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/route_transition.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/interaction/tv_key_bindings.dart';
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

  /// TV：图片区焦点与工具栏首按钮焦点。
  final _imageFocus = FocusNode(debugLabel: 'tv-preview-image');
  final _toolbarFocus = FocusNode(debugLabel: 'tv-preview-toolbar');

  static const _minScale = 1.0;
  static const _maxScale = 4.0;
  static const _doubleTapScale = 2.5;

  bool get _isTelevision =>
      AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false;

  double get _currentScale => _transform.value.getMaxScaleOnAxis();

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
    _imageFocus.dispose();
    _toolbarFocus.dispose();
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

  /// 围绕预览中心缩放，并约束图片边缘；缩回原尺寸时恢复居中。
  void _zoomBy(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(_minScale, _maxScale).toDouble();
    final viewport = MediaQuery.sizeOf(context);
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final sceneCenter = _transform.toScene(center);
    final nextTransform = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(next, next, 1, 1)
      ..translateByDouble(-sceneCenter.dx, -sceneCenter.dy, 0, 1);
    _transform.value = _clampTransform(nextTransform, viewport);
  }

  /// 还原图片位置与缩放，不触发重新加载。
  void _resetZoom() => _transform.value = Matrix4.identity();

  /// TV：缩放大于 1 时按视口 10% 平移并钳制边缘；未放大时不平移。
  void _panPreview(Offset delta) {
    if (_currentScale <= 1.05) return;
    final size = MediaQuery.sizeOf(context);
    final center = Offset(size.width / 2, size.height / 2);
    final scale = _currentScale;
    final anchor =
        _transform.toScene(center) - Offset(delta.dx / scale, delta.dy / scale);
    final next = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1);
    _transform.value = _clampTransform(next, size);
  }

  /// 原地约束变换：超出视口的轴不露边，未铺满的轴保持居中。
  Matrix4 _clampTransform(Matrix4 next, Size size) {
    final display = _containedSize(size, widget.item.aspectRatio);
    final origin = Offset(
      (size.width - display.width) / 2,
      (size.height - display.height) / 2,
    );
    final topLeft = MatrixUtils.transformPoint(next, origin);
    final bottomRight = MatrixUtils.transformPoint(
      next,
      origin + Offset(display.width, display.height),
    );
    var shift = Offset.zero;
    if (bottomRight.dx - topLeft.dx <= size.width) {
      shift += Offset(size.width / 2 - (topLeft.dx + bottomRight.dx) / 2, 0);
    } else if (topLeft.dx > 0) {
      shift -= Offset(topLeft.dx, 0);
    } else if (bottomRight.dx < size.width) {
      shift += Offset(size.width - bottomRight.dx, 0);
    }
    if (bottomRight.dy - topLeft.dy <= size.height) {
      shift += Offset(0, size.height / 2 - (topLeft.dy + bottomRight.dy) / 2);
    } else if (topLeft.dy > 0) {
      shift -= Offset(0, topLeft.dy);
    } else if (bottomRight.dy < size.height) {
      shift += Offset(0, size.height - bottomRight.dy);
    }
    if (shift != Offset.zero) {
      next.setEntry(0, 3, next.entry(0, 3) + shift.dx);
      next.setEntry(1, 3, next.entry(1, 3) + shift.dy);
    }
    return next;
  }

  /// TV 统一返回意图：先还原放大状态，再一次 Back 才关闭。
  void _handleTvBack() {
    if (_currentScale > 1.05) {
      _resetZoom();
      return;
    }
    unawaited(_close());
  }

  /// TV 图片区按键：方向平移、OK 回工具栏。
  KeyEventResult _onImageKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent &&
        !const [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ].contains(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    final size = MediaQuery.sizeOf(context);
    final step = Offset(size.width * 0.1, size.height * 0.1);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _panPreview(Offset(-step.dx, 0));
      case LogicalKeyboardKey.arrowRight:
        _panPreview(Offset(step.dx, 0));
      case LogicalKeyboardKey.arrowUp:
        _panPreview(Offset(0, -step.dy));
      case LogicalKeyboardKey.arrowDown:
        _panPreview(Offset(0, step.dy));
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        // OK 回工具栏。
        _toolbarFocus.requestFocus();
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
        _handleTvBack();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
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

    final isTv = _isTelevision;
    final chromeWidget = _PreviewChrome(
      onDetails: () => unawaited(_close(ImagePreviewAction.openDetails)),
      onClose: () => unawaited(_close()),
      // TV：显式缩放工具与首按钮焦点；普通端保持两个动作。
      television: isTv,
      zoomIn: () => _zoomBy(1.25),
      zoomOut: () => _zoomBy(0.8),
      onReset: _resetZoom,
      toolbarFocusNode: _toolbarFocus,
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
      // TV 工具栏使用安全边距，避免过扫描裁切焦点。
      top: isTv ? top + size.height * 0.05 : top + LumaSpacing.xs,
      left: isTv ? size.width * 0.05 : LumaSpacing.xs,
      right: isTv ? size.width * 0.05 : LumaSpacing.xs,
      child: isTv
          ? Focus(
              canRequestFocus: false,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _imageFocus.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: chromeContent,
            )
          : chromeContent,
    );

    final backdrop = ColoredBox(color: context.luma.playerInk);
    final content = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // TV：Back/Esc 先还原放大状态再一次关闭；普通端直接关闭。
        const SingleActivator(LogicalKeyboardKey.escape): isTv
            ? _handleTvBack
            : () => unawaited(_close()),
        const SingleActivator(LogicalKeyboardKey.equal, shift: true): () =>
            _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
            _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.minus): () => _zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
            _zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.digit0): _resetZoom,
      },
      child: Focus(
        autofocus: !isTv,
        skipTraversal: isTv,
        child: PopScope(
          canPop: _closing,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            // TV 先还原放大状态再一次关闭；普通端直接关闭。
            if (isTv) {
              _handleTvBack();
            } else {
              unawaited(_close());
            }
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
                    hint: isTv ? '方向键缩放平移，OK 回到工具栏' : '可双指或滚轮缩放，双击放大，按 0 还原',
                    child: isTv
                        ? Focus(
                            focusNode: _imageFocus,
                            onKeyEvent: _onImageKeyEvent,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onDoubleTapDown: (details) =>
                                  _doubleTapDetails = details,
                              onDoubleTap: _onDoubleTap,
                              child: InteractiveViewer(
                                transformationController: _transform,
                                minScale: _minScale,
                                maxScale: _maxScale,
                                clipBehavior: Clip.none,
                                child: SizedBox(
                                  width: size.width,
                                  height: size.height,
                                  child: Center(child: preview),
                                ),
                              ),
                            ),
                          )
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTapDown: (details) =>
                                _doubleTapDetails = details,
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
        ),
      ),
    );
    return isTv ? TvKeyBindings(child: content) : content;
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
  const _PreviewChrome({
    required this.onDetails,
    required this.onClose,
    this.television = false,
    this.zoomIn,
    this.zoomOut,
    this.onReset,
    this.toolbarFocusNode,
  });

  final VoidCallback onDetails;
  final VoidCallback onClose;

  /// TV：放大/缩小/还原与详情、关闭都成为可见可聚焦动作，首按钮持焦点。
  final bool television;
  final VoidCallback? zoomIn;
  final VoidCallback? zoomOut;
  final VoidCallback? onReset;
  final FocusNode? toolbarFocusNode;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    var chromeStyle = IconButton.styleFrom(
      backgroundColor: extras.badgeScrim,
      foregroundColor: extras.onPlayerInk,
    );
    if (television) {
      // TV 控件最小 56dp，保证观看距离可点中。
      chromeStyle = chromeStyle.copyWith(
        minimumSize: const WidgetStatePropertyAll(
          Size(LumaTvLayout.controlMinHeight, LumaTvLayout.controlMinHeight),
        ),
      );
    }
    final detailsButton = IconButton.filledTonal(
      tooltip: '详情',
      style: chromeStyle,
      onPressed: onDetails,
      icon: const Icon(Icons.info_outline_rounded),
    );
    final closeButton = IconButton.filledTonal(
      tooltip: '关闭',
      style: chromeStyle,
      onPressed: onClose,
      icon: const Icon(Icons.close_rounded),
    );
    if (!television) {
      return Row(children: [detailsButton, const Spacer(), closeButton]);
    }
    return Row(
      children: [
        // 首按钮持焦点，弹窗打开即可用方向键在工具间移动。
        IconButton.filledTonal(
          focusNode: toolbarFocusNode,
          autofocus: true,
          tooltip: '放大',
          style: chromeStyle,
          onPressed: zoomIn,
          icon: const Icon(Icons.zoom_in_rounded),
        ),
        const SizedBox(width: LumaSpacing.xs),
        IconButton.filledTonal(
          tooltip: '缩小',
          style: chromeStyle,
          onPressed: zoomOut,
          icon: const Icon(Icons.zoom_out_rounded),
        ),
        const SizedBox(width: LumaSpacing.xs),
        IconButton.filledTonal(
          tooltip: '还原',
          style: chromeStyle,
          onPressed: onReset,
          icon: const Icon(Icons.aspect_ratio_rounded),
        ),
        const SizedBox(width: LumaSpacing.xs),
        detailsButton,
        const Spacer(),
        closeButton,
      ],
    );
  }
}
