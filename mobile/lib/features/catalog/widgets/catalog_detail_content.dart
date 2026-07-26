// 作品详情内容区负责组织首屏、资料、演职员、版本和选集。
// 它不持有网络或收藏状态，所有变化通过页面传入的不可变数据与回调完成。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import 'catalog_detail_hero.dart';
import 'catalog_detail_sections.dart';
import 'catalog_detail_theme.dart';

/// 呈现已加载作品的可滚动详情内容，并保留页面传入的播放与收藏回调。
class CatalogDetailContent extends StatelessWidget {
  /// 组合详情首屏与资料区，并把可选海报标签传给首屏 Hero。
  const CatalogDetailContent({
    super.key,
    required this.item,
    this.heroTag,
    required this.loadDetailArtwork,
    required this.favorite,
    required this.savingFavorite,
    required this.onPlay,
    required this.onPlayFromStart,
    required this.onToggleFavorite,
  });

  final CatalogItem item;
  final String? heroTag;

  /// 为 false 时只复用轻量海报，避免路由过渡期间解码大背景图。
  final bool loadDetailArtwork;

  final bool favorite;
  final bool savingFavorite;
  final ValueChanged<String> onPlay;
  final ValueChanged<String> onPlayFromStart;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final episodeRows = item.kind == CatalogKind.series
        ? _episodeRows(item)
        : const <_EpisodeListRow>[];
    return Theme(
      data: catalogDetailTheme(context),
      child: CustomScrollView(
        cacheExtent: LumaLayout.scrollCacheExtent,
        slivers: [
          SliverToBoxAdapter(
            child: CatalogDetailHero(
              item: item,
              heroTag: heroTag,
              loadBackdrop: loadDetailArtwork,
              favorite: favorite,
              savingFavorite: savingFavorite,
              onPlay: onPlay,
              onPlayFromStart: onPlayFromStart,
              onToggleFavorite: onToggleFavorite,
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LumaLayout.detailMaxWidth,
                ),
                child: Padding(
                  padding: LumaLayout.pagePadding(
                    top: 0,
                    bottom: item.kind == CatalogKind.series
                        ? 0
                        : LumaLayout.pagePaddingBottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (item.overview.isNotEmpty) ...[
                        const CatalogSectionHeading(title: '简介'),
                        const SizedBox(height: LumaSpacing.sm),
                        Text(
                          item.overview,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: CatalogDetailPalette.text,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.1,
                              ),
                        ),
                        if (item.countries.isNotEmpty ||
                            item.certification.isNotEmpty) ...[
                          const SizedBox(height: LumaSpacing.md),
                          Text(
                            [
                              ...item.countries.map((country) => country.name),
                              if (item.certification.isNotEmpty)
                                item.certification,
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: CatalogDetailPalette.muted),
                          ),
                        ],
                        const SizedBox(height: LumaSpacing.xl),
                      ],
                      if (item.credits.isNotEmpty) ...[
                        const CatalogSectionHeading(title: '演职员'),
                        const SizedBox(height: LumaSpacing.md),
                        CatalogCreditStrip(credits: item.credits),
                        const SizedBox(height: LumaSpacing.xl),
                      ],
                      if (item.kind == CatalogKind.movie &&
                          item.versions.isNotEmpty) ...[
                        CatalogSectionHeading(
                          title: '本库其他版本',
                          trailing: '${item.versions.length} 个可播放版本',
                        ),
                        const SizedBox(height: LumaSpacing.sm),
                        ...item.versions.map(
                          (version) => CatalogVersionTile(
                            version: version,
                            onPlay: () => onPlay(version.mediaId),
                          ),
                        ),
                        const SizedBox(height: LumaSpacing.lg),
                      ],
                      if (item.kind == CatalogKind.series) ...[
                        CatalogSectionHeading(
                          title: '选集',
                          trailing: '${item.episodeCount} 集',
                        ),
                        const SizedBox(height: LumaSpacing.md),
                      ],
                      if (item.kind != CatalogKind.series &&
                          item.metadataStatus.isNotEmpty &&
                          item.metadataStatus != 'ready') ...[
                        const SizedBox(height: LumaSpacing.md),
                        CatalogMetadataStatus(status: item.metadataStatus),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (episodeRows.isNotEmpty)
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final outside =
                    ((constraints.crossAxisExtent - LumaLayout.detailMaxWidth)
                        .clamp(0, double.infinity)) /
                    2;
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    outside + LumaLayout.pagePaddingH,
                    0,
                    outside + LumaLayout.pagePaddingH,
                    item.metadataStatus.isEmpty ||
                            item.metadataStatus == 'ready'
                        ? LumaLayout.pagePaddingBottom
                        : 0,
                  ),
                  sliver: SliverList.builder(
                    itemCount: episodeRows.length,
                    itemBuilder: (context, index) =>
                        switch (episodeRows[index]) {
                          _SeasonHeadingRow(:final label) => Padding(
                            padding: const EdgeInsets.only(
                              top: LumaSpacing.lg,
                              bottom: LumaSpacing.sm,
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _EpisodeItemRow(:final episode) => CatalogEpisodeTile(
                            key: ValueKey(episode.id),
                            episode: episode,
                            onTap: () => onPlay(episode.mediaId),
                          ),
                        },
                  ),
                );
              },
            ),
          if (item.kind == CatalogKind.series &&
              item.metadataStatus.isNotEmpty &&
              item.metadataStatus != 'ready')
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: LumaLayout.detailMaxWidth,
                  ),
                  child: Padding(
                    padding: LumaLayout.pagePadding(top: LumaSpacing.md),
                    child: CatalogMetadataStatus(status: item.metadataStatus),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<_EpisodeListRow> _episodeRows(CatalogItem item) {
    final rows = <_EpisodeListRow>[];
    int? season;
    for (final episode in item.episodes) {
      if (season != episode.seasonNumber) {
        season = episode.seasonNumber;
        rows.add(_SeasonHeadingRow(season == 0 ? '特别篇' : '第 $season 季'));
      }
      rows.add(_EpisodeItemRow(episode));
    }
    return rows;
  }
}

sealed class _EpisodeListRow {
  const _EpisodeListRow();
}

final class _SeasonHeadingRow extends _EpisodeListRow {
  const _SeasonHeadingRow(this.label);

  final String label;
}

final class _EpisodeItemRow extends _EpisodeListRow {
  const _EpisodeItemRow(this.episode);

  final CatalogEpisode episode;
}
