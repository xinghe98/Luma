import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../shared/media/authenticated_media_image.dart';

class CatalogCard extends StatelessWidget {
  const CatalogCard({super.key, required this.item, required this.onTap});

  final CatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = item.kind == CatalogKind.series
        ? '${item.episodeCount} 集 · 已看 ${item.completedCount} 集'
        : [
            if (item.year != null) '${item.year}',
            if (item.completed) '已看完',
          ].join(' · ');
    return Semantics(
      button: true,
      label: '${item.title}，$subtitle',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LumaRadii.large),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  final cacheWidth = (constraints.maxWidth * dpr).round().clamp(
                    1,
                    640,
                  );
                  final cacheHeight = (constraints.maxHeight * dpr)
                      .round()
                      .clamp(1, 960);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(LumaRadii.large),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AuthenticatedMediaImage(
                          path: item.posterUrl,
                          cacheWidth: cacheWidth,
                          cacheHeight: cacheHeight,
                          fallback: ColoredBox(
                            color: scheme.surfaceContainerHigh,
                            child: Icon(
                              item.kind == CatalogKind.movie
                                  ? Icons.movie_outlined
                                  : Icons.tv_outlined,
                              size: 42,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (item.progress > 0 && !item.completed)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              value: item.progress,
                              minHeight: 3,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: LumaSpacing.xs),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: LumaSpacing.xxs),
            Text(
              subtitle.isEmpty
                  ? (item.kind == CatalogKind.movie ? '电影' : '剧集')
                  : subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
