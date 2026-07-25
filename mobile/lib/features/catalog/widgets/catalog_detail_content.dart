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
  const CatalogDetailContent({
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
  Widget build(BuildContext context) => Theme(
    data: catalogDetailTheme(context),
    child: CustomScrollView(
      cacheExtent: LumaLayout.scrollCacheExtent,
      slivers: [
        SliverToBoxAdapter(
          child: CatalogDetailHero(
            item: item,
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
              constraints: const BoxConstraints(maxWidth: LumaLayout.detailMaxWidth),
              child: Padding(
                padding: LumaLayout.pagePadding(top: 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (item.overview.isNotEmpty) ...[
                      const CatalogSectionHeading(title: '简介'),
                      const SizedBox(height: LumaSpacing.sm),
                      Text(
                        item.overview,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                            if (item.certification.isNotEmpty) item.certification,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: CatalogDetailPalette.muted,
                          ),
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
                      ..._episodeTiles(item),
                    ],
                    if (item.metadataStatus.isNotEmpty &&
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
      ],
    ),
  );

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
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      }
      yield CatalogEpisodeTile(
        episode: episode,
        onTap: () => onPlay(episode.mediaId),
      );
    }
  }
}
