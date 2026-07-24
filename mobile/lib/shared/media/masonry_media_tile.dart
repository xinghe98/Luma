import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import 'authenticated_media_image.dart';
import 'luma_favorite_button.dart';

/// 瀑布流瓷砖：仅封面 + 可选收藏，无标题/元数据条。
class MasonryMediaTile extends StatelessWidget {
  const MasonryMediaTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.onFavorite,
    this.heroTag,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFavorite;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final rawRatio = item.aspectRatio > 0.05 ? item.aspectRatio : 1.0;
        final ratio = rawRatio.clamp(0.25, 4.0);
        final height = width / ratio;
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (width * dpr).round().clamp(1, 640);
        final cacheHeight = (height * dpr).round().clamp(1, 1280);
        final placeholder = _MasonryPlaceholder(item: item);
        final radius = BorderRadius.circular(LumaRadii.small);

        return Semantics(
          button: true,
          label: item.title,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              // Hero 过渡期间保留的默认水波纹会像一层灰色蒙版。
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              borderRadius: radius,
              child: ClipRRect(
                borderRadius: radius,
                child: SizedBox(
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _tileImage(
                        placeholder: placeholder,
                        cacheWidth: cacheWidth,
                        cacheHeight: cacheHeight,
                      ),
                      if (onFavorite != null)
                        Positioned(
                          right: LumaSpacing.xxs,
                          top: LumaSpacing.xxs,
                          child: LumaFavoriteButton(
                            isFavorite: item.isFavorite,
                            onPressed: onFavorite,
                            overlay: true,
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

  Widget _tileImage({
    required Widget placeholder,
    required int cacheWidth,
    required int cacheHeight,
  }) {
    final image = item.thumbnailUrl.isNotEmpty
        ? AuthenticatedMediaImage(
            path: item.thumbnailUrl,
            fit: BoxFit.cover,
            fallback: placeholder,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            // 照片的 EXIF 方向或探测尺寸可能与最终解码方向不同；两边都
            // 强制指定会拉伸像素。仅将它们作为等比解码上限。
            resizePolicy: ResizeImagePolicy.fit,
          )
        : placeholder;
    if (heroTag == null) return image;
    return Hero(
      tag: heroTag!,
      child: Material(type: MaterialType.transparency, child: image),
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
