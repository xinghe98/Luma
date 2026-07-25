import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/api_catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/formatters/duration_formatter.dart';
import '../../shared/media/authenticated_media_image.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';

class CatalogDetailPage extends StatefulWidget {
  const CatalogDetailPage({
    super.key,
    required this.catalogId,
    this.initialItem,
    required this.repository,
    required this.onOpenMedia,
  });

  final String catalogId;
  final CatalogItem? initialItem;
  final CatalogRepository repository;
  final ValueChanged<String> onOpenMedia;

  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  CatalogItem? _item;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final item = await widget.repository.detail(widget.catalogId);
      if (mounted) {
        setState(() {
          _item = item;
          _loading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      appBar: AppBar(title: Text(item?.title ?? '作品详情')),
      body: item == null
          ? _error == null
                ? const DetailPageSkeleton(artworkAspectRatio: 16 / 9)
                : ErrorState(onRetry: _load)
          : Stack(
              children: [
                ListView(
                  padding: LumaLayout.pagePadding(top: LumaSpacing.xs),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: LumaLayout.detailMaxWidth,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                LumaRadii.large,
                              ),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: AuthenticatedMediaImage(
                                  path: item.backdropUrl.isEmpty
                                      ? item.thumbnailUrl
                                      : item.backdropUrl,
                                  fallback: ColoredBox(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHigh,
                                    child: Icon(
                                      item.kind == CatalogKind.movie
                                          ? Icons.movie_outlined
                                          : Icons.tv_outlined,
                                      size: 72,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: LumaSpacing.lg),
                            Text(
                              item.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: LumaSpacing.xs),
                            Text(
                              _summary(item),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (item.overview.isNotEmpty) ...[
                              const SizedBox(height: LumaSpacing.md),
                              Text(item.overview),
                            ],
                            if (item.genres.isNotEmpty ||
                                item.communityRating != null ||
                                item.certification.isNotEmpty) ...[
                              const SizedBox(height: LumaSpacing.md),
                              _MetadataSummary(item: item),
                            ],
                            if (item.credits.isNotEmpty) ...[
                              const SizedBox(height: LumaSpacing.lg),
                              Text(
                                '演职员',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: LumaSpacing.xs),
                              Text(
                                item.credits
                                    .take(6)
                                    .map((credit) => credit.character.isEmpty
                                        ? credit.name
                                        : '${credit.name} · ${credit.character}')
                                    .join('、'),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (item.metadataStatus.isNotEmpty &&
                                item.metadataStatus != 'ready') ...[
                              const SizedBox(height: LumaSpacing.md),
                              _MetadataStatus(status: item.metadataStatus),
                            ],
                            const SizedBox(height: LumaSpacing.lg),
                            FilledButton.icon(
                              onPressed: item.playableMediaId.isEmpty
                                  ? null
                                  : () => widget.onOpenMedia(
                                      item.playableMediaId,
                                    ),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                item.kind == CatalogKind.series
                                    ? '播放下一集'
                                    : item.progress > 0 && !item.completed
                                    ? '继续播放'
                                    : '播放',
                              ),
                            ),
                            if (item.kind == CatalogKind.series) ...[
                              const SizedBox(height: LumaSpacing.xl),
                              Text(
                                '选集',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: LumaSpacing.md),
                              ..._episodeTiles(item),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_loading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
    );
  }

  Iterable<Widget> _episodeTiles(CatalogItem item) sync* {
    int? season;
    for (final episode in item.episodes) {
      if (season != episode.seasonNumber) {
        season = episode.seasonNumber;
        yield Padding(
          padding: const EdgeInsets.only(
            top: LumaSpacing.lg,
            bottom: LumaSpacing.sm,
          ),
          child: Text(
            season == 0 ? '特别篇' : '第 $season 季',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
      }
      yield Padding(
        padding: const EdgeInsets.only(bottom: LumaSpacing.sm),
        child: _EpisodeTile(
          episode: episode,
          onTap: () => widget.onOpenMedia(episode.mediaId),
        ),
      );
    }
  }

  String _summary(CatalogItem item) {
    if (item.kind == CatalogKind.movie) {
      return [
        if (item.year != null) '${item.year}',
        if (item.durationMs != null)
          formatDuration(Duration(milliseconds: item.durationMs!)),
        if (item.resolution.isNotEmpty) item.resolution,
      ].join(' · ');
    }
    return [
      '${item.episodeCount} 集',
      '已看 ${item.completedCount} 集',
      if (item.resolution.isNotEmpty) '下集 ${item.resolution}',
    ].join(' · ');
  }
}

class _MetadataSummary extends StatelessWidget {
  const _MetadataSummary({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final details = [
      ...item.genres.map((genre) => genre.name),
      if (item.communityRating != null)
        '评分 ${item.communityRating!.toStringAsFixed(1)}',
      if (item.certification.isNotEmpty) item.certification,
    ];
    return Text(
      details.join(' · '),
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _MetadataStatus extends StatelessWidget {
  const _MetadataStatus({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final message = switch (status) {
      'pending' => '资料等待更新',
      'refreshing' => '资料正在更新',
      'needs_review' => '资料匹配需要确认',
      'failed' => '资料暂时无法更新',
      _ => '资料状态更新中',
    };
    return Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, required this.onTap});

  final CatalogEpisode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final metadata = [
      if (episode.durationMs != null)
        formatDuration(Duration(milliseconds: episode.durationMs!)),
      if (episode.resolution.isNotEmpty) episode.resolution,
    ].join(' · ');

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(LumaRadii.medium),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(LumaSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 104,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(LumaRadii.small),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: AuthenticatedMediaImage(
                      path: episode.thumbnailUrl,
                      fallback: ColoredBox(
                        color: scheme.surfaceContainerHigh,
                        child: const Icon(Icons.play_circle_outline_rounded),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: LumaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '第 ${episode.episodeNumber} 集 · ${episode.title}',
                      style: textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: LumaSpacing.xs),
                      Text(
                        metadata,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: LumaSpacing.sm),
              Icon(
                episode.completed
                    ? Icons.check_circle_rounded
                    : Icons.play_arrow_rounded,
                color: episode.completed
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
