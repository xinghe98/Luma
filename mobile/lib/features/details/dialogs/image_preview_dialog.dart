import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/route_transition.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/interaction/tv_key_bindings.dart';
import '../../../shared/media/authenticated_media_image.dart';
import '../../../shared/media/image_gallery_controller.dart';
import '../widgets/image_preview_navigation.dart';

/// 图片预览关闭后交还给调用方的后续动作。
enum ImagePreviewAction { openDetails }

/// 打开不透明的全屏图片预览，支持缩放、还原、进入详情和画廊切换。
/// 有 [heroTag] 时从来源缩略图原地放大；无来源时退化为短淡入。
/// 传入 [gallery] 后预览跟随控制器显示当前图片，可切换上一张/下一张；
/// 控制器生命周期由调用方负责，预览不销毁它。
Future<ImagePreviewAction?> showImagePreviewDialog(
  BuildContext context,
  MediaItem item, {
  String? heroTag,
  ImageGalleryController? gallery,
}) async {
  final route = PageRouteBuilder<ImagePreviewAction>(
    opaque: true,
    settings: const RouteSettings(name: 'image-preview'),
    transitionsBuilder: (_, _, _, child) => child,
    transitionDuration: LumaMotion.forContext(context, LumaMotion.slow),
    reverseTransitionDuration: LumaMotion.forContext(context, LumaMotion.slow),
    pageBuilder: (context, animation, secondaryAnimation) {
      return ImagePreviewDialog(item: item, heroTag: heroTag, gallery: gallery);
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
  /// 传入 [gallery] 后显示控制器当前图片并允许切换；画廊状态由调用方持有。
  const ImagePreviewDialog({
    super.key,
    required this.item,
    this.heroTag,
    this.gallery,
  });

  final MediaItem item;
  final String? heroTag;

  /// 画廊控制器；为空时为单图预览，不出现切换入口。
  final ImageGalleryController? gallery;

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

  /// TV：画廊上一张/下一张按钮焦点，纳入遥控器焦点顺序。
  final _prevFocus = FocusNode(debugLabel: 'tv-preview-prev');
  final _nextFocus = FocusNode(debugLabel: 'tv-preview-next');

  // 原始触摸事件只记录滑动，不与 InteractiveViewer 争抢缩放和平移手势。
  Offset _swipeDelta = Offset.zero;
  int _activeTouchPointers = 0;
  bool _multitouchGesture = false;
  bool _swipeStartedUnscaled = false;

  /// 已用于布局图片子树的 ID，识别真实切图与加载状态通知。
  String? _shownItemId;

  static const _minScale = 1.0;
  static const _maxScale = 4.0;
  static const _doubleTapScale = 2.5;

  /// 未缩放时横向滑动超过该距离才切图，避免误触与点击冲突。
  static const _swipeSwitchDistance = 64.0;

  bool get _isTelevision =>
      AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false;

  double get _currentScale => _transform.value.getMaxScaleOnAxis();

  ImageGalleryController? get _gallery => widget.gallery;

  /// 画廊模式下跟随控制器当前图片；单图模式恒为入口图片。
  MediaItem get _displayedItem => _gallery?.currentItem ?? widget.item;

  /// 只有仍在显示最初入口图片时才允许 Hero 回到来源卡片，
  /// 否则反向飞行会带着别的图片缩回错误的缩略图。
  bool get _heroShowsSource =>
      widget.heroTag != null && _displayedItem.id == widget.item.id;

  @override
  void initState() {
    super.initState();
    _shownItemId = _displayedItem.id;
    widget.gallery?.addListener(_onGalleryChanged);
  }

  @override
  void didUpdateWidget(ImagePreviewDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gallery != widget.gallery) {
      oldWidget.gallery?.removeListener(_onGalleryChanged);
      widget.gallery?.addListener(_onGalleryChanged);
    }
    if (_shownItemId != _displayedItem.id) {
      _shownItemId = _displayedItem.id;
      _transform.value = Matrix4.identity();
    }
  }

  /// 画廊通知：只有当前图片 ID 变化才重置缩放并重建图片子树，
  /// 远端分页的加载/失败通知不打断当前浏览。
  void _onGalleryChanged() {
    if (!mounted) return;
    final id = _displayedItem.id;
    if (id == _shownItemId) return;
    _shownItemId = id;
    _transform.value = Matrix4.identity();
    setState(() {});
  }

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
    // 画廊控制器由调用方持有，这里只退订不销毁。
    widget.gallery?.removeListener(_onGalleryChanged);
    _transform.dispose();
    _imageFocus.dispose();
    _toolbarFocus.dispose();
    _prevFocus.dispose();
    _nextFocus.dispose();
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

  /// 记录单指滑动的起点状态；一旦加入第二根手指，本轮只处理缩放和平移。
  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (_activeTouchPointers == 0) {
      _swipeDelta = Offset.zero;
      _multitouchGesture = false;
      _swipeStartedUnscaled = _currentScale <= 1.05;
    }
    _activeTouchPointers++;
    if (_activeTouchPointers > 1) _multitouchGesture = true;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch &&
        _activeTouchPointers == 1 &&
        !_multitouchGesture &&
        _swipeStartedUnscaled) {
      _swipeDelta += event.delta;
    }
  }

  /// 松手后仅切一张；取消、纵向滑动、捏合和放大状态均不切图。
  void _onPointerUp(PointerEvent event) {
    if (event.kind != PointerDeviceKind.touch || _activeTouchPointers == 0) {
      return;
    }
    if (event is PointerCancelEvent) _multitouchGesture = true;
    _activeTouchPointers--;
    if (_activeTouchPointers != 0) return;
    final delta = _swipeDelta;
    final canSwipe =
        !_multitouchGesture &&
        _swipeStartedUnscaled &&
        _currentScale <= 1.05 &&
        delta.dx.abs() >= _swipeSwitchDistance &&
        delta.dx.abs() > delta.dy.abs() * 1.5;
    _swipeDelta = Offset.zero;
    _multitouchGesture = false;
    _swipeStartedUnscaled = false;
    if (canSwipe) _navigateGallery(delta.dx < 0);
  }

  /// 键盘与 TV 共用的切图入口；忙碌时控制器内部串行/忽略，失败保留当前图。
  void _navigateGallery(bool forward) {
    final gallery = _gallery;
    if (gallery == null || _closing) return;
    if (forward) {
      if (!gallery.canNext) return;
      unawaited(gallery.next());
    } else {
      if (!gallery.canPrevious) return;
      gallery.previous();
    }
  }

  /// 原地约束变换：超出视口的轴不露边，未铺满的轴保持居中。
  Matrix4 _clampTransform(Matrix4 next, Size size) {
    final display = _containedSize(size, _displayedItem.aspectRatio);
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

  /// TV 图片区按键：放大时方向键平移，未放大时左右切换、OK 先到导航条。
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
    final zoomed = _currentScale > 1.05;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        // 放大时平移，未放大时向左切上一张。
        if (zoomed) {
          _panPreview(Offset(-step.dx, 0));
        } else {
          _navigateGallery(false);
        }
      case LogicalKeyboardKey.arrowRight:
        if (zoomed) {
          _panPreview(Offset(step.dx, 0));
        } else {
          _navigateGallery(true);
        }
      case LogicalKeyboardKey.arrowUp:
        _panPreview(Offset(0, -step.dy));
      case LogicalKeyboardKey.arrowDown:
        _panPreview(Offset(0, step.dy));
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        // OK：画廊模式优先把焦点落到下一张按钮，再向下进入工具栏。
        if (_gallery != null) {
          _nextFocus.requestFocus();
        } else {
          _toolbarFocus.requestFocus();
        }
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
    // 画廊模式下跟随控制器当前图片；单图模式恒为入口图片。
    final item = _displayedItem;
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
    // 缩略图始终垫底，原图只在转场完成后叠加，退出前先移除。
    // 整棵图片子树按当前 ID 换 key，上一张的解码/淡入状态不会渗入下一张。
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
    // 只有仍显示入口图片时才允许 Hero；切到其他图后不再携带来源标签，
    // 关闭时也就不会带着别的图片飞回最初的缩略图。
    final heroThumbnail = _heroShowsSource
        ? Hero(
            tag: widget.heroTag!,
            createRectTween: _straightRectTween,
            flightShuttleBuilder: _thumbnailFlightShuttle,
            child: thumbnail,
          )
        : thumbnail;
    final image = SizedBox(
      key: ValueKey('preview-image-${item.id}'),
      width: displaySize.width,
      height: displaySize.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          heroThumbnail,
          if (_originalLoadAllowed && !_closing && originalPath.isNotEmpty)
            AuthenticatedMediaImage(
              key: ValueKey('original-${item.id}'),
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

    // 无 Hero（无来源标签或已切到其他图）时保留短淡入降级动效。
    final preview = !_heroShowsSource && routeAnimation != null
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
      // TV：显式缩放工具与首按钮焦点；普通端也提供同一组缩放动作。
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
      top: isTv ? null : 0,
      bottom: isTv ? size.height * 0.05 : null,
      left: isTv ? size.width * 0.05 : 0,
      right: isTv ? size.width * 0.05 : 0,
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

    // 画廊导航条：独立底部区域，与顶部缩放工具互不挤压；
    // TV 上抬到底部工具栏之上，保持遥控器可达且不重叠。
    final gallery = _gallery;
    final navigation = gallery == null
        ? null
        : Positioned(
            left: isTv ? size.width * 0.05 : 0,
            right: isTv ? size.width * 0.05 : 0,
            bottom: isTv ? size.height * 0.05 + 96 : 0,
            child: ImagePreviewNavigationBar(
              gallery: gallery,
              television: isTv,
              previousFocusNode: _prevFocus,
              nextFocusNode: _nextFocus,
            ),
          );
    final backdrop = ColoredBox(color: context.luma.playerInk);
    // Windows/桌面键盘左右切换；TV 上焦点在按钮上时左右键负责移动焦点，
    // 图片区的方向切图由 _onImageKeyEvent 处理，不挂全局快捷键。
    final bindings = <ShortcutActivator, VoidCallback>{
      // TV：Back/Esc 先还原放大状态再一次关闭；普通端直接关闭。
      const SingleActivator(LogicalKeyboardKey.escape): isTv
          ? _handleTvBack
          : () => unawaited(_close()),
      const SingleActivator(LogicalKeyboardKey.equal, shift: true): () =>
          _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.numpadAdd): () => _zoomBy(1.25),
      const SingleActivator(LogicalKeyboardKey.minus): () => _zoomBy(0.8),
      const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
          _zoomBy(0.8),
      const SingleActivator(LogicalKeyboardKey.digit0): _resetZoom,
      if (!isTv) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _navigateGallery(false),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _navigateGallery(true),
      },
    };
    final content = CallbackShortcuts(
      bindings: bindings,
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
                    hint: isTv
                        ? '方向键缩放平移或切图，OK 进入导航与工具栏'
                        : '可双指或滚轮缩放，双击放大，左右滑动或方向键切换，按 0 还原',
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
                        : Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _onPointerDown,
                            onPointerMove: _onPointerMove,
                            onPointerUp: _onPointerUp,
                            onPointerCancel: _onPointerUp,
                            child: GestureDetector(
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
                  ),
                  ?navigation,
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
      // 普通端顶栏：底部遮罩反转为顶部渐变，缩放与详情、关闭同一排。
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: LumaGradients.bottomScrim(extras.playerInk).colors,
            stops: LumaGradients.bottomScrim(extras.playerInk).stops,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LumaSpacing.xs,
              LumaSpacing.xs,
              LumaSpacing.xs,
              LumaSpacing.xl,
            ),
            child: Row(
              children: [
                detailsButton,
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: '放大',
                  style: chromeStyle,
                  onPressed: zoomIn,
                  icon: const Icon(Icons.zoom_in_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: '缩小',
                  style: chromeStyle,
                  onPressed: zoomOut,
                  icon: const Icon(Icons.zoom_out_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: '还原',
                  style: chromeStyle,
                  onPressed: onReset,
                  icon: const Icon(Icons.fit_screen_rounded),
                ),
                const SizedBox(width: LumaSpacing.xs),
                closeButton,
              ],
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: extras.badgeScrim,
        borderRadius: BorderRadius.circular(LumaRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _TvPreviewAction(
              focusNode: toolbarFocusNode,
              autofocus: true,
              tooltip: '放大',
              label: '放大',
              icon: Icons.zoom_in_rounded,
              onPressed: zoomIn,
            ),
            _TvPreviewAction(
              tooltip: '缩小',
              label: '缩小',
              icon: Icons.zoom_out_rounded,
              onPressed: zoomOut,
            ),
            _TvPreviewAction(
              tooltip: '还原',
              label: '还原',
              icon: Icons.aspect_ratio_rounded,
              onPressed: onReset,
            ),
            _TvPreviewAction(
              tooltip: '详情',
              label: '详情',
              icon: Icons.info_outline_rounded,
              onPressed: onDetails,
            ),
            const Spacer(),
            _TvPreviewAction(
              tooltip: '关闭',
              label: '关闭',
              icon: Icons.close_rounded,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _TvPreviewAction extends StatelessWidget {
  const _TvPreviewAction({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton.icon(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}
