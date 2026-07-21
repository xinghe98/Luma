import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import 'authenticated_media_image.dart';

/// 瀑布流瓷砖：仅封面 + 可选收藏，无标题/元数据条。
class MasonryMediaTile extends StatelessWidget {
  const MasonryMediaTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.onFavorite,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final rawRatio = item.aspectRatio > 0.05 ? item.aspectRatio : 1.0;
        // 防止异常元数据生成无限高瓷砖，同时保留常见全景与长图比例。
        final ratio = rawRatio.clamp(0.25, 4.0);
        final height = width / ratio;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (width * dpr).round().clamp(1, 640);
        final cacheHeight = (height * dpr).round().clamp(1, 1280);
        final placeholder = _MasonryPlaceholder(item: item);

        return Semantics(
          button: true,
          label: item.title,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(LumaRadii.small),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(LumaRadii.small),
                child: SizedBox(
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.thumbnailUrl.isNotEmpty)
                        AuthenticatedMediaImage(
                          path: item.thumbnailUrl,
                          fit: BoxFit.cover,
                          fallback: placeholder,
                          cacheWidth: cacheWidth,
                          cacheHeight: cacheHeight,
                        )
                      else
                        placeholder,
                      if (onFavorite != null)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.35,
                              ),
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                              minimumSize: const Size(32, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            tooltip: item.isFavorite ? '取消收藏' : '收藏',
                            onPressed: onFavorite,
                            icon: Icon(
                              item.isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MasonryPlaceholder extends StatelessWidget {
  const _MasonryPlaceholder({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 28,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          semanticLabel: item.title,
        ),
      ),
    );
  }
}
