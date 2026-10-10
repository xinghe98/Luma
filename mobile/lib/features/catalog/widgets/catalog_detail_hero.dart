// 作品详情影院首屏负责背景、海报、身份资料和首要操作。
// 它只读取 CatalogItem，不直接请求图片或持久化收藏状态。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../../../shared/layout/adaptive_action_width.dart';
import '../../../shared/media/authenticated_media_image.dart';
import 'catalog_card.dart';

// 断点与海报尺寸集中在文件顶部，避免在布局分支里散落魔法数。
const _posterWide = 208.0;
const _posterCompact = 128.0;
const _posterTiny = 104.0;
const _identityStackBreakpoint = 260.0;
const _posterShrinkBreakpoint = 360.0;

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
    this.television = false,
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

  /// TV：主播放/从头播放/收藏在首次有效内容时获得初始焦点。
  final bool television;

  @override
  Widget build(BuildContext context) => television
      ? _TvCatalogHero(
          item: item,
          heroTag: heroTag,
          loadBackdrop: loadBackdrop,
          favorite: favorite,
          savingFavorite: savingFavorite,
          onPlay: onPlay,
          onPlayFromStart: onPlayFromStart,
          onToggleFavorite: onToggleFavorite,
        )
      : LayoutBuilder(
          builder: (context, constraints) {
            final isWide =
                constraints.maxWidth >= LumaLayout.detailTwoColumnBreakpoint;
            // 资料区始终与海报并列，常规手机宽度仅缩小海报而不改成上下结构。
            // 这样评分、时长和标签会持续处于海报右侧的同一视觉组。
            final stackIdentity =
                constraints.maxWidth < _identityStackBreakpoint;
            final posterWidth = isWide
                ? _posterWide
                : constraints.maxWidth < _posterShrinkBreakpoint
                ? _posterTiny
                : _posterCompact;
            final scheme = Theme.of(context).colorScheme;
            final backdropFallback = ColoredBox(
              color: scheme.surfaceContainerLow,
            );
            final posterContent = _HeroPoster(item: item);
            final poster = SizedBox(
              width: posterWidth,
              child: heroTag == null
                  ? posterContent
                  : Hero(
                      tag: heroTag!,
                      createRectTween: CatalogCard.straightRectTween,
                      flightShuttleBuilder:
                          CatalogCard.preserveSourceHeroFlight,
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
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LumaGradients.heroFade(scheme.surface),
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
                              Align(
                                alignment: Alignment.centerLeft,
                                child: poster,
                              ),
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
                              child: _PrimaryPlayButton(
                                item: item,
                                onPlay: onPlay,
                              ),
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

// 电视首屏以横幅与观看动作为中心，海报和完整身份资料放在横幅下方。
// 背景沿用路由结算开关，来源海报沿用原来的缩略图与 Hero 飞行约束。
class _TvCatalogHero extends StatelessWidget {
  const _TvCatalogHero({
    required this.item,
    required this.heroTag,
    required this.loadBackdrop,
    required this.favorite,
    required this.savingFavorite,
    required this.onPlay,
    required this.onPlayFromStart,
    required this.onToggleFavorite,
  });

  final CatalogItem item;
  final String? heroTag;
  final bool loadBackdrop;
  final bool favorite;
  final bool savingFavorite;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onPlayFromStart;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final poster = _HeroPoster(item: item);
    final canPlay = item.playableMediaId.isNotEmpty;
    final metadata = [
      if (item.year != null) '${item.year}',
      if (item.kind == CatalogKind.movie && item.durationMs != null)
        formatDuration(Duration(milliseconds: item.durationMs!)),
      if (item.kind == CatalogKind.series) '${item.episodeCount} 集',
      if (item.resolution.isNotEmpty) item.resolution,
      if (item.communityRating != null)
        '★ ${item.communityRating!.toStringAsFixed(1)}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          key: const ValueKey('tv-catalog-cinematic-header'),
          children: [
            Positioned.fill(
              child: loadBackdrop
                  ? AuthenticatedMediaImage(
                      path: item.backdropUrl.isEmpty
                          ? item.thumbnailUrl
                          : item.backdropUrl,
                      cacheWidth: 1280,
                      fit: BoxFit.cover,
                      fallback: ColoredBox(color: colors.surface),
                    )
                  : ColoredBox(color: colors.surface),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LumaGradients.sideFade(colors.surface),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: const EdgeInsets.all(LumaSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: LumaTvLayout.heroMinHeight,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: constraints.maxWidth >= LumaTvLayout.detailSplitWidth
                          ? constraints.maxWidth * 0.65
                          : constraints.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineLarge,
                          ),
                          const SizedBox(height: LumaSpacing.sm),
                          Text(
                            metadata.join(' · '),
                            style: theme.textTheme.bodyLarge,
                          ),
                          const SizedBox(height: LumaSpacing.xl),
                          Wrap(
                            spacing: LumaSpacing.md,
                            runSpacing: LumaSpacing.sm,
                            children: [
                              FilledButton.icon(
                                key: const ValueKey('tv-catalog-play'),
                                autofocus: canPlay,
                                onFocusChange: _revealTvAction,
                                onPressed: canPlay
                                    ? () => onPlay(item.playableMediaId)
                                    : null,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(
                                  item.progressMs > 0 ? '继续观看' : '播放',
                                ),
                              ),
                              OutlinedButton.icon(
                                autofocus: !canPlay && !savingFavorite,
                                onFocusChange: _revealTvAction,
                                onPressed: savingFavorite
                                    ? null
                                    : onToggleFavorite,
                                icon: Icon(
                                  favorite
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                ),
                                label: Text(favorite ? '已收藏' : '加入喜欢'),
                              ),
                              if (_startMediaId(item).isNotEmpty)
                                TextButton.icon(
                                  onFocusChange: _revealTvAction,
                                  onPressed: () =>
                                      onPlayFromStart(_startMediaId(item)),
                                  icon: const Icon(Icons.replay_rounded),
                                  label: const Text('从头播放'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          key: const ValueKey('tv-catalog-identity'),
          padding: const EdgeInsets.all(LumaSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: heroTag == null
                    ? poster
                    : Hero(
                        tag: heroTag!,
                        createRectTween: CatalogCard.straightRectTween,
                        flightShuttleBuilder:
                            CatalogCard.preserveSourceHeroFlight,
                        child: poster,
                      ),
              ),
              const SizedBox(width: LumaSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.originalTitle.isNotEmpty &&
                        item.originalTitle != item.title)
                      Text(
                        item.originalTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    const SizedBox(height: LumaSpacing.sm),
                    Text(
                      [
                        ...item.genres.map((genre) => genre.name),
                        ...item.countries.map((country) => country.name),
                        if (item.certification.isNotEmpty) item.certification,
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
    final canPlayFromStart = _startMediaId(item).isNotEmpty;
    final children = [
      OutlinedButton.icon(
        onPressed: canPlayFromStart
            ? () => onPlayFromStart(_startMediaId(item))
            : null,
        icon: const Icon(Icons.replay_rounded),
        label: const Text('从头播放'),
        style: _secondaryActionStyle(context),
      ),
      OutlinedButton.icon(
        onPressed: savingFavorite ? null : onToggleFavorite,
        icon: Icon(
          favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        ),
        label: Text(favorite ? '已收藏' : '加入喜欢'),
        style: _secondaryActionStyle(context),
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

  ButtonStyle _secondaryActionStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.styleFrom(
      foregroundColor: scheme.onSurface,
      side: BorderSide(color: scheme.outline),
      minimumSize: const Size(0, LumaLayout.buttonHeight),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumaRadii.medium),
      ),
    );
  }
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
        fallback: Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return ColoredBox(
              color: scheme.surfaceContainerLow,
              child: Icon(
                item.kind == CatalogKind.movie
                    ? Icons.movie_outlined
                    : Icons.tv_outlined,
                color: scheme.onSurfaceVariant,
                size: 52,
              ),
            );
          },
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: scheme.onSurface,
          ),
        ),
        if (item.originalTitle.isNotEmpty && item.originalTitle != item.title)
          Padding(
            padding: const EdgeInsets.only(top: LumaSpacing.xxs),
            child: Text(
              item.originalTitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          details.join(' · '),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
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
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(LumaRadii.small),
                      ),
                      child: Text(
                        genre.name,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: scheme.onSurface),
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
        label: Text(item.progressMs > 0 ? '继续观看' : '播放'),
        style: FilledButton.styleFrom(
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

/// 获焦后揭示实际按钮；刷新没有焦点变化时不会改变用户所在位置。
void _revealTvAction(bool focused) {
  if (!focused) return;
  final node = FocusManager.instance.primaryFocus;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = node?.context;
    if (context != null && context.mounted && node!.hasPrimaryFocus) {
      Scrollable.ensureVisible(context, alignment: 0.5);
    }
  });
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
