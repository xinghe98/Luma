import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/api_catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/formatters/duration_formatter.dart';
import '../../shared/media/authenticated_media_image.dart';
import '../../shared/states/error_state.dart';

class CatalogDetailPage extends StatefulWidget {
  const CatalogDetailPage({
    super.key,
    required this.catalogId,
    required this.repository,
    required this.onOpenMedia,
  });

  final String catalogId;
  final CatalogRepository repository;
  final ValueChanged<String> onOpenMedia;

  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  CatalogItem? _item;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final item = await widget.repository.detail(widget.catalogId);
      if (mounted) setState(() => _item = item);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      appBar: AppBar(title: Text(item?.title ?? '作品详情')),
      body: item == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : ErrorState(onRetry: _load)
          : ListView(
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
                          borderRadius: BorderRadius.circular(LumaRadii.large),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: AuthenticatedMediaImage(
                              path: item.thumbnailUrl,
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
                        const SizedBox(height: LumaSpacing.lg),
                        FilledButton.icon(
                          onPressed: item.playableMediaId.isEmpty
                              ? null
                              : () => widget.onOpenMedia(item.playableMediaId),
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
                          const SizedBox(height: LumaSpacing.sm),
                          ..._episodeTiles(item),
                        ],
                      ],
                    ),
                  ),
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
          padding: const EdgeInsets.only(top: LumaSpacing.md),
          child: Text(
            season == 0 ? '特别篇' : '第 $season 季',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        );
      }
      yield ListTile(
        contentPadding: EdgeInsets.zero,
        minTileHeight: 64,
        leading: SizedBox(
          width: 88,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LumaRadii.small),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: AuthenticatedMediaImage(
                path: episode.thumbnailUrl,
                fallback: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: const Icon(Icons.play_circle_outline_rounded),
                ),
              ),
            ),
          ),
        ),
        title: Text('第 ${episode.episodeNumber} 集 · ${episode.title}'),
        subtitle: _episodeMetadata(episode),
        trailing: Icon(
          episode.completed
              ? Icons.check_circle_rounded
              : Icons.play_arrow_rounded,
        ),
        onTap: () => widget.onOpenMedia(episode.mediaId),
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

  Widget? _episodeMetadata(CatalogEpisode episode) {
    final metadata = [
      if (episode.durationMs != null)
        formatDuration(Duration(milliseconds: episode.durationMs!)),
      if (episode.resolution.isNotEmpty) episode.resolution,
    ];
    return metadata.isEmpty ? null : Text(metadata.join(' · '));
  }
}
