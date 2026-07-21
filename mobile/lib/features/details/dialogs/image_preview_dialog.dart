import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/media_item.dart';
import '../../../shared/media/authenticated_media_image.dart';
import '../../../shared/media/media_artwork.dart';

/// 全屏图片预览：双指缩放、双击放大/还原，可选进入详情。
void showImagePreviewDialog(
  BuildContext context,
  MediaItem item, {
  VoidCallback? onOpenDetails,
}) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (context) => ImagePreviewDialog(
      item: item,
      onOpenDetails: onOpenDetails,
    ),
  );
}

class ImagePreviewDialog extends StatefulWidget {
  const ImagePreviewDialog({
    super.key,
    required this.item,
    this.onOpenDetails,
  });

  final MediaItem item;
  final VoidCallback? onOpenDetails;

  @override
  State<ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<ImagePreviewDialog> {
  final _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;

  static const _minScale = 1.0;
  static const _maxScale = 4.0;
  static const _doubleTapScale = 2.5;

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

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final top = MediaQuery.paddingOf(context).top;
    final fallback = MediaArtwork(item: item, borderRadius: 0);
    final path = (item.originalUrl != null && item.originalUrl!.isNotEmpty)
        ? item.originalUrl!
        : item.thumbnailUrl;
    // 原图预览允许放大，但限制解码尺寸以免高像素照片耗尽移动端内存。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final size = MediaQuery.sizeOf(context);
    final cacheWidth = (size.width * dpr * _maxScale).round().clamp(1, 4096);
    final cacheHeight = (size.height * dpr * _maxScale).round().clamp(1, 4096);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onDoubleTapDown: (details) => _doubleTapDetails = details,
              onDoubleTap: _onDoubleTap,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: _minScale,
                maxScale: _maxScale,
                clipBehavior: Clip.none,
                child: SizedBox.expand(
                  child: AuthenticatedMediaImage(
                    path: path,
                    fit: BoxFit.contain,
                    fullResolution: true,
                    cacheWidth: cacheWidth,
                    cacheHeight: cacheHeight,
                    fallback: fallback,
                  ),
                ),
              ),
            ),
            Positioned(
              top: top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  if (widget.onOpenDetails != null)
                    IconButton.filledTonal(
                      tooltip: '详情',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onOpenDetails!();
                      },
                      icon: const Icon(Icons.info_outline_rounded),
                    )
                  else
                    const Spacer(),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: '关闭',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
