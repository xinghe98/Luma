// 作品详情影院首屏负责背景、海报、身份资料和首要操作。
// 它只读取 CatalogItem，不直接请求图片或持久化收藏状态。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../../../shared/media/authenticated_media_image.dart';
import 'catalog_detail_theme.dart';

/// 以叠层构图显示横幅、海报、标题信息和播放操作。
class CatalogDetailHero extends StatelessWidget {
  const CatalogDetailHero({
    super.key,
    required this.item,
    required this.favorite,
    required this.savingFavorite,
    required this.onPlay,
    required this.onPlayFromStart,
    required this.onToggleFavorite,
  });

  final CatalogItem item;
  final bool favorite;
  final bool savingFavorite;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onPlayFromStart;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isWide =
          constraints.maxWidth >= LumaLayout.detailTwoColumnBreakpoint;
      final posterWidth = isWide ? 208.0 : 136.0;
      final posterLeft = isWide
          ? ((constraints.maxWidth - LumaLayout.detailMaxWidth).clamp(
                      0,
                      double.infinity,
                    ) /
                    2) +
                LumaSpacing.lg
          : LumaSpacing.lg;
      final informationLeft = posterLeft + posterWidth + LumaSpacing.md;
      return SizedBox(
        height: 592,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AuthenticatedMediaImage(
              path: item.backdropUrl.isEmpty
                  ? item.thumbnailUrl
                  : item.backdropUrl,
              cacheWidth: 1280,
              fallback: ColoredBox(
                color: CatalogDetailPalette.surface,
                child: Icon(
                  item.kind == CatalogKind.movie
                      ? Icons.movie_outlined
                      : Icons.tv_outlined,
                  color: CatalogDetailPalette.muted,
                  size: 76,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x26000000),
                    Color(0xAA121310),
                    CatalogDetailPalette.background,
                  ],
                  stops: [0, .57, 1],
                ),
              ),
            ),
            Positioned(
              left: posterLeft,
              top: 160,
              width: posterWidth,
              child: _HeroPoster(item: item),
            ),
            Positioned(
              left: informationLeft,
              right: LumaSpacing.md,
              top: 246,
              child: _HeroInformation(item: item),
            ),
            Positioned(
              left: LumaSpacing.lg,
              right: LumaSpacing.lg,
              top: 440,
              child: _PrimaryPlayButton(item: item, onPlay: onPlay),
            ),
            Positioned(
              left: LumaSpacing.lg,
              right: LumaSpacing.lg,
              top: 508,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _startMediaId(item).isEmpty
                          ? null
                          : () => onPlayFromStart(_startMediaId(item)),
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('从头播放'),
                      style: _secondaryActionStyle(),
                    ),
                  ),
                  const SizedBox(width: LumaSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: savingFavorite ? null : onToggleFavorite,
                      icon: Icon(
                        favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                      label: Text(favorite ? '已收藏' : '加入喜欢'),
                      style: _secondaryActionStyle(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  ButtonStyle _secondaryActionStyle() => OutlinedButton.styleFrom(
    foregroundColor: CatalogDetailPalette.text,
    side: const BorderSide(color: CatalogDetailPalette.outline),
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LumaRadii.medium),
    ),
  );
}

class _HeroPoster extends StatelessWidget {
  const _HeroPoster({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(LumaRadii.large),
    child: AspectRatio(
      aspectRatio: 2 / 3,
      child: AuthenticatedMediaImage(
        path: item.posterUrl,
        cacheWidth: 480,
        fallback: ColoredBox(
          color: CatalogDetailPalette.surface,
          child: Icon(
            item.kind == CatalogKind.movie
                ? Icons.movie_outlined
                : Icons.tv_outlined,
            color: CatalogDetailPalette.muted,
            size: 52,
          ),
        ),
      ),
    ),
  );
}

class _HeroInformation extends StatelessWidget {
  const _HeroInformation({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (item.year != null) '${item.year}',
      if (item.kind == CatalogKind.movie && item.durationMs != null)
        formatDuration(Duration(milliseconds: item.durationMs!)),
      if (item.kind == CatalogKind.series) '${item.episodeCount} 集',
      if (item.resolution.isNotEmpty) item.resolution,
      if (item.certification.isNotEmpty) item.certification,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: CatalogDetailPalette.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (item.originalTitle.isNotEmpty && item.originalTitle != item.title)
          Padding(
            padding: const EdgeInsets.only(top: LumaSpacing.xxs),
            child: Text(
              item.originalTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CatalogDetailPalette.muted,
              ),
            ),
          ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          details.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: CatalogDetailPalette.muted),
        ),
        if (item.communityRating != null || item.genres.isNotEmpty) ...[
          const SizedBox(height: LumaSpacing.sm),
          Wrap(
            spacing: LumaSpacing.xs,
            runSpacing: LumaSpacing.xs,
            children: [
              if (item.communityRating != null)
                Text(
                  '★ ${item.communityRating!.toStringAsFixed(1)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: CatalogDetailPalette.accent,
                  ),
                ),
              ...item.genres
                  .take(2)
                  .map(
                    (genre) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LumaSpacing.sm,
                        vertical: LumaSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B382C),
                        borderRadius: BorderRadius.circular(LumaRadii.small),
                      ),
                      child: Text(
                        genre.name,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: CatalogDetailPalette.text),
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PrimaryPlayButton extends StatelessWidget {
  const _PrimaryPlayButton({required this.item, required this.onPlay});

  final CatalogItem item;
  final ValueChanged<String> onPlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton.icon(
        onPressed: item.playableMediaId.isEmpty
            ? null
            : () => onPlay(item.playableMediaId),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('继续观看'),
        style: FilledButton.styleFrom(
          backgroundColor: CatalogDetailPalette.accent,
          foregroundColor: CatalogDetailPalette.background,
          textStyle: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LumaRadii.medium),
          ),
        ),
      ),
    );
  }
}

/// 电视剧优先从正片第一季开始，只有没有正片时才回退到特别篇。
String _startMediaId(CatalogItem item) {
  if (item.kind != CatalogKind.series || item.episodes.isEmpty) {
    return item.playableMediaId;
  }
  final indexed = item.episodes
      .where((episode) => episode.mediaId.isNotEmpty)
      .toList();
  final episodes = indexed.any((episode) => episode.seasonNumber > 0)
      ? indexed.where((episode) => episode.seasonNumber > 0).toList()
      : indexed;
  episodes.sort((left, right) {
    final season = left.seasonNumber.compareTo(right.seasonNumber);
    return season == 0
        ? left.episodeNumber.compareTo(right.episodeNumber)
        : season;
  });
  return episodes.isEmpty ? item.playableMediaId : episodes.first.mediaId;
}
