import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import 'media_badge.dart';
import 'authenticated_media_image.dart';

class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    super.key,
    required this.item,
    this.borderRadius = LumaRadii.medium,
    this.useCardThumbnail = false,
  });

  final MediaItem item;
  final double borderRadius;
  final bool useCardThumbnail;

  static const _palettes = [
    [Color(0xFF45606A), Color(0xFF17232D), Color(0xFFB89162)],
    [Color(0xFF5D536C), Color(0xFF1E2634), Color(0xFF9E7C77)],
    [Color(0xFF345A57), Color(0xFF152A31), Color(0xFF91A9A0)],
    [Color(0xFF6A5346), Color(0xFF29252B), Color(0xFFC4A16C)],
    [Color(0xFF445A72), Color(0xFF171D29), Color(0xFF7B9EAE)],
  ];

  @override
  Widget build(BuildContext context) {
    final imagePath = useCardThumbnail && item.cardThumbnailUrl.isNotEmpty
        ? item.cardThumbnailUrl
        : item.thumbnailUrl;
    final palette = _palettes[item.artSeed % _palettes.length];
    final placeholder = _PlaceholderArtwork(
      item: item,
      palette: palette,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 真实封面盖住占位；加载中/失败时露出下方占位，避免装饰圆叠在图上。
          if (imagePath.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final dpr = MediaQuery.devicePixelRatioOf(context);
                final logicalWidth = constraints.maxWidth;
                final logicalHeight = constraints.maxHeight;
                // 卡片同时约束物理宽高，避免竖图解码最终会被 cover 裁掉的像素。
                final cacheWidth = logicalWidth.isFinite && logicalWidth > 0
                    ? (logicalWidth * dpr).round().clamp(1, 640)
                    : null;
                final cacheHeight = useCardThumbnail &&
                        logicalHeight.isFinite &&
                        logicalHeight > 0
                    ? (logicalHeight * dpr).round().clamp(1, 400)
                    : null;
                return AuthenticatedMediaImage(
                  path: imagePath,
                  fit: BoxFit.cover,
                  fallback: placeholder,
                  cacheWidth: cacheWidth,
                  cacheHeight: cacheHeight,
                );
              },
            )
          else
            placeholder,
          if (item.isPortrait)
            const Positioned(
              left: 10,
              top: 10,
              child: MediaBadge(label: '竖屏'),
            ),
        ],
      ),
    );
  }
}

/// 无缩略图时的渐变占位（含装饰形状）；有图时不应叠在封面上。
class _PlaceholderArtwork extends StatelessWidget {
  const _PlaceholderArtwork({required this.item, required this.palette});

  final MediaItem item;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette[0], palette[1]],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -34,
            top: -42,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette[2].withAlpha(70),
              ),
            ),
          ),
          Positioned(
            left: item.isPortrait ? 54 : -35,
            bottom: -65,
            child: Transform.rotate(
              angle: -0.25,
              child: Container(
                width: item.isPortrait ? 110 : 210,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(80),
                  border: Border.all(
                    color: Colors.white.withAlpha(35),
                    width: 2,
                  ),
                  color: palette[0].withAlpha(90),
                ),
              ),
            ),
          ),
          Center(
            child: Icon(
              item.type == MediaType.video
                  ? Icons.play_circle_outline_rounded
                  : Icons.image_outlined,
              size: 38,
              color: Colors.white.withAlpha(175),
            ),
          ),
        ],
      ),
    );
  }
}
