import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../shared/media/authenticated_media_image.dart';

/// 打开作品详情，并可携带来源海报的 Hero 标签。
typedef CatalogOpenCallback =
    void Function(CatalogItem item, {String? heroTag});

class CatalogCard extends StatelessWidget {
  /// 构建作品卡片；提供 [heroTag] 时海报会参与到详情页的共享元素过渡。
  const CatalogCard({
    super.key,
    required this.item,
    required this.onTap,
    this.heroTag,
  });

  final CatalogItem item;
  final VoidCallback onTap;
  final String? heroTag;

  /// 为作品海报生成稳定标签；同一路由内同一作品只能出现一次。
  static String heroTagFor(CatalogItem item) =>
      'catalog-${item.kind.name}-${item.id}';

  /// 让海报沿最短直线路径缩放，避免起点与落点接近时出现弧线漂移。
  static RectTween straightRectTween(Rect? begin, Rect? end) =>
      RectTween(begin: begin, end: end);

  /// Hero 飞行期间保留列表端海报，避免详情大图或反向来源尚未解码时闪回占位。
  static Widget preserveSourceHeroFlight(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final endpoint = flightDirection == HeroFlightDirection.push
        ? fromHeroContext.widget as Hero
        : toHeroContext.widget as Hero;
    return endpoint.child;
  }

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
        // 详情页立即入场，避免默认水波纹在海报上留下短暂蒙层。
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
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
                  final artwork = ClipRRect(
                    borderRadius: BorderRadius.circular(LumaRadii.large),
                    child: Material(
                      type: MaterialType.transparency,
                      child: AuthenticatedMediaImage(
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
                    ),
                  );
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(LumaRadii.large),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (heroTag == null)
                          artwork
                        else
                          Hero(
                            tag: heroTag!,
                            createRectTween: straightRectTween,
                            flightShuttleBuilder: preserveSourceHeroFlight,
                            child: artwork,
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
