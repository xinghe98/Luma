import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/media/authenticated_media_image.dart';

/// 全屏图片预览：双指缩放、双击放大/还原，可选进入详情。
/// [heroTag] 与来源缩略图一致时启用共享元素过渡，避免生硬弹出。
void showImagePreviewDialog(
  BuildContext context,
  MediaItem item, {
  VoidCallback? onOpenDetails,
  String? heroTag,
}) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // 小尺寸图片按比例显示时，预览外区域使用实底，不能透出媒体瀑布流。
    barrierColor: context.luma.playerInk,
    transitionDuration: LumaMotion.forContext(context, LumaMotion.fast),
    pageBuilder: (context, animation, secondaryAnimation) {
      return ImagePreviewDialog(
        item: item,
        onOpenDetails: onOpenDetails,
        heroTag: heroTag,
      );
    },
    // 图片由 Hero 负责位移动画；实底遮罩由 barrier 淡入，整页不再额外 Fade，
    // 避免与 Hero 叠加造成闪一下。
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
  );
}

class ImagePreviewDialog extends StatefulWidget {
  const ImagePreviewDialog({
    super.key,
    required this.item,
    this.onOpenDetails,
    this.heroTag,
  });

  final MediaItem item;
  final VoidCallback? onOpenDetails;
  final String? heroTag;

  @override
  State<ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<ImagePreviewDialog> {
  final _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;
  bool _originalReady = false;
  bool _originalLoadAllowed = false;

  static const _minScale = 1.0;
  static const _maxScale = 4.0;
  static const _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    if (widget.heroTag == null) {
      _originalLoadAllowed = true;
    } else {
      _allowOriginalLoadAfterTransition();
    }
  }

  Future<void> _allowOriginalLoadAfterTransition() async {
    await Future<void>.delayed(LumaMotion.fast);
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

  void _markOriginalReady() {
    if (mounted && !_originalReady) setState(() => _originalReady = true);
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

    final originalPath =
        (item.originalUrl != null && item.originalUrl!.isNotEmpty)
        ? item.originalUrl!
        : item.thumbnailUrl;
    final thumbPath = item.thumbnailUrl;
    final hasDistinctOriginal =
        originalPath.isNotEmpty && originalPath != thumbPath;

    // 缩略图垫底（列表里通常已缓存，首帧即可 contain 铺开），原图叠上淡入。
    // 避免原先 MediaArtwork(cover) → 原图(contain) 的比例跳变闪动。
    final image = Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (thumbPath.isNotEmpty && (!hasDistinctOriginal || !_originalReady))
          AuthenticatedMediaImage(
            path: thumbPath,
            fit: BoxFit.contain,
            cacheWidth: thumbCacheWidth,
            cacheHeight: thumbCacheHeight,
            resizePolicy: ResizeImagePolicy.fit,
            fallback: const SizedBox.expand(),
          ),
        if (_originalLoadAllowed && hasDistinctOriginal)
          AuthenticatedMediaImage(
            path: originalPath,
            fit: BoxFit.contain,
            fullResolution: true,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            fadeInDuration: LumaMotion.normal,
            resizePolicy: ResizeImagePolicy.fit,
            onImageLoaded: _markOriginalReady,
            fallback: const SizedBox.expand(),
          )
        else if (_originalLoadAllowed && originalPath.isNotEmpty)
          AuthenticatedMediaImage(
            path: originalPath,
            fit: BoxFit.contain,
            fullResolution: true,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            resizePolicy: ResizeImagePolicy.fit,
            fallback: const SizedBox.expand(),
          ),
      ],
    );

    final heroChild = Material(type: MaterialType.transparency, child: image);
    final preview = widget.heroTag == null
        ? heroChild
        : Hero(tag: widget.heroTag!, child: heroChild);

    final chrome = routeAnimation == null
        ? _PreviewChrome(top: top, onOpenDetails: widget.onOpenDetails)
        : FadeTransition(
            opacity: CurvedAnimation(
              parent: routeAnimation,
              curve: const Interval(0.45, 1, curve: Curves.easeOut),
              reverseCurve: const Interval(0, 0.55, curve: Curves.easeIn),
            ),
            child: _PreviewChrome(
              top: top,
              onOpenDetails: widget.onOpenDetails,
            ),
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        // 使用独立的播放环境底色，保证小图预览不会露出底层内容。
        color: context.luma.playerInk,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              image: true,
              label: '图片预览：${item.title}',
              hint: '可双指缩放或双击放大',
              child: GestureDetector(
                onDoubleTapDown: (details) => _doubleTapDetails = details,
                onDoubleTap: _onDoubleTap,
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  clipBehavior: Clip.none,
                  child: SizedBox.expand(child: preview),
                ),
              ),
            ),
            chrome,
          ],
        ),
      ),
    );
  }
}

class _PreviewChrome extends StatelessWidget {
  const _PreviewChrome({required this.top, this.onOpenDetails});

  final double top;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    final chromeStyle = IconButton.styleFrom(
      backgroundColor: extras.badgeScrim,
      foregroundColor: extras.onPlayerInk,
    );
    return Positioned(
      top: top + LumaSpacing.xs,
      left: LumaSpacing.xs,
      right: LumaSpacing.xs,
      child: Row(
        children: [
          if (onOpenDetails != null)
            IconButton.filledTonal(
              tooltip: '详情',
              style: chromeStyle,
              onPressed: () {
                Navigator.pop(context);
                onOpenDetails!();
              },
              icon: const Icon(Icons.info_outline_rounded),
            )
          else
            const Spacer(),
          const Spacer(),
          IconButton.filledTonal(
            tooltip: '关闭',
            style: chromeStyle,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
