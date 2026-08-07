// 作品详情影院首屏负责背景、海报、身份资料和首要操作。
// 它只读取 CatalogItem，不直接请求图片或持久化收藏状态。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../../../shared/layout/adaptive_action_width.dart';
import '../../../shared/media/authenticated_media_image.dart';
import 'catalog_card.dart';
import 'catalog_detail_theme.dart';

/// 以自然高度布局横幅、海报、标题信息和播放操作，适配窄屏与大字体。
class CatalogDetailHero extends StatelessWidget {
  /// 构建作品详情首屏；[heroTag] 仅连接来源海报，不叠加页面位移动画。
  const CatalogDetailHero({
    super.key,
    required this.item,
    this.heroTag,
    required this.loadBackdrop,
    required this.favorite,
    required this.savingFavorite,
    required this.onPlay,
    required this.onPlayFromStart,
    required this.onToggleFavorite,
  });

  final CatalogItem item;
  final String? heroTag;

  /// 路由过渡结束后才加载大背景图，等待期间保持稳定底色。
  final bool loadBackdrop;

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
      // 资料区始终与海报并列，常规手机宽度仅缩小海报而不改成上下结构。
      // 这样评分、时长和标签会持续处于海报右侧的同一视觉组。
      final stackIdentity = constraints.maxWidth < 260;
      final posterWidth = isWide
          ? 208.0
          : constraints.maxWidth < 360
          ? 104.0
          : 128.0;
      const backdropFallback = ColoredBox(color: CatalogDetailPalette.surface);
      final posterContent = _HeroPoster(item: item);
      final poster = SizedBox(
        width: posterWidth,
        child: heroTag == null
            ? posterContent
            : Hero(
                tag: heroTag!,
                createRectTween: CatalogCard.straightRectTween,
                flightShuttleBuilder: CatalogCard.preserveSourceHeroFlight,
                child: posterContent,
              ),
      );
      final information = _HeroInformation(item: item);
      return Stack(
        children: [
          Positioned.fill(
            child: loadBackdrop
                ? AuthenticatedMediaImage(
                    path: item.backdropUrl.isEmpty
                        ? item.thumbnailUrl
                        : item.backdropUrl,
                    cacheWidth: isWide ? 1280 : 960,
                    fadeInDuration: LumaMotion.forContext(
                      context,
                      LumaMotion.normal,
                    ),
                    fallback: backdropFallback,
                  )
                : backdropFallback,
          ),
          const Positioned.fill(
            child: DecoratedBox(
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
          ),
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LumaLayout.detailMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LumaSpacing.lg,
                    kToolbarHeight + LumaSpacing.xl,
                    LumaSpacing.lg,
                    LumaSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (stackIdentity) ...[
                        Align(alignment: Alignment.centerLeft, child: poster),
                        const SizedBox(height: LumaSpacing.lg),
                        information,
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            poster,
                            const SizedBox(width: LumaSpacing.md),
                            Expanded(child: information),
                          ],
                        ),
                      const SizedBox(height: LumaSpacing.xl),
                      AdaptiveActionWidth(
                        child: _PrimaryPlayButton(item: item, onPlay: onPlay),
                      ),
                      const SizedBox(height: LumaSpacing.sm),
                      AdaptiveActionWidth(
                        child: _SecondaryActions(
                          item: item,
                          vertical: stackIdentity,
                          favorite: favorite,
                          savingFavorite: savingFavorite,
                          onPlayFromStart: onPlayFromStart,
                          onToggleFavorite: onToggleFavorite,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions({
    required this.item,
    required this.vertical,
    required this.favorite,
    required this.savingFavorite,
    required this.onPlayFromStart,
    required this.onToggleFavorite,
  });

  final CatalogItem item;
  final bool vertical;
  final bool favorite;
  final bool savingFavorite;
  final ValueChanged<String> onPlayFromStart;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final children = [
      OutlinedButton.icon(
        onPressed: _startMediaId(item).isEmpty
            ? null
            : () => onPlayFromStart(_startMediaId(item)),
        icon: const Icon(Icons.replay_rounded),
        label: const Text('从头播放'),
        style: _secondaryActionStyle(),
      ),
      OutlinedButton.icon(
        onPressed: savingFavorite ? null : onToggleFavorite,
        icon: Icon(
          favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        ),
        label: Text(favorite ? '已收藏' : '加入喜欢'),
        style: _secondaryActionStyle(),
      ),
    ];
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          children.first,
          const SizedBox(height: LumaSpacing.sm),
          children.last,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: children.first),
        const SizedBox(width: LumaSpacing.sm),
        Expanded(child: children.last),
      ],
    );
  }

  ButtonStyle _secondaryActionStyle() => OutlinedButton.styleFrom(
    foregroundColor: CatalogDetailPalette.text,
    side: const BorderSide(color: CatalogDetailPalette.outline),
    minimumSize: const Size(0, LumaLayout.buttonHeight),
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CatalogDetailPalette.muted,
              ),
            ),
          ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          details.join(' · '),
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
                        color: CatalogDetailPalette.surfaceHigh,
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
      child: FilledButton.icon(
        onPressed: item.playableMediaId.isEmpty
            ? null
            : () => onPlay(item.playableMediaId),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('继续观看'),
        style: FilledButton.styleFrom(
          backgroundColor: CatalogDetailPalette.accent,
          foregroundColor: CatalogDetailPalette.onAccent,
          minimumSize: const Size(0, LumaLayout.buttonHeight),
          textStyle: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
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
