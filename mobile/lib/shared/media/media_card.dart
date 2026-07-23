import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import '../formatters/date_formatter.dart';
import '../formatters/duration_formatter.dart';
import 'luma_favorite_button.dart';
import 'media_artwork.dart';
import 'media_badge.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onFavorite,
    this.compact = false,
    this.heroTag,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final bool compact;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final duration = formatDuration(item.duration);
    final coverRadius = context.luma.coverRadius;
    final artwork = heroTag == null
        ? MediaArtwork(item: item, useCardThumbnail: true)
        : Hero(
            tag: heroTag!,
            child: MediaArtwork(item: item, useCardThumbnail: true),
          );
    return Semantics(
      button: true,
      label: item.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(coverRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(coverRadius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    artwork,
                    if (item.type == MediaType.video && duration.isNotEmpty)
                      Positioned(
                        right: LumaSpacing.xs,
                        bottom: item.progress > 0
                            ? LumaSpacing.sm
                            : LumaSpacing.xs,
                        child: MediaBadge(label: duration),
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
                    if (item.progress > 0 && item.type == MediaType.video)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: item.progress,
                          minHeight: 3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: LumaSpacing.xs),
            Text(
              item.title,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: LumaSpacing.xxs),
            Text(
              item.type == MediaType.video
                  ? '${item.resolution} · ${formatMediaDate(item.addedAt)}'
                  : '${item.resolution} · 图片',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
