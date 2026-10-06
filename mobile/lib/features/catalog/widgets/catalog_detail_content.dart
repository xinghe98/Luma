// 作品详情内容区负责组织首屏、资料、演职员、版本和选集。
// 它不持有网络或收藏状态，所有变化通过页面传入的不可变数据与回调完成。
// TV：版本/选集纳入焦点集合（几百集可遍历），纯文字长区域提供可聚焦滚动。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../shared/interaction/tv_focus_collection.dart';
import '../../../shared/media/tv_media_grid.dart';
import '../../details/widgets/tv_scrollable_detail_region.dart';
import 'catalog_detail_hero.dart';
import 'catalog_detail_sections.dart';
import 'catalog_detail_theme.dart';

/// 呈现已加载作品的可滚动详情内容，并保留页面传入的播放与收藏回调。
class CatalogDetailContent extends StatefulWidget {
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
    this.television = false,
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

  /// TV：版本/选集接入焦点集合，长文字区域可聚焦滚动。
  final bool television;

  @override
  State<CatalogDetailContent> createState() => _CatalogDetailContentState();
}

class _CatalogDetailContentState extends State<CatalogDetailContent> {
  final _scroll = ScrollController();
  TvListReveal? _tvReveal;
  List<String>? _tvItemIds;
  final _versionKeys = <String, GlobalKey>{};

  // 布局和离屏揭示使用同一份当前字体几何。
  double _tvEpisodeRowExtent = 0;
  double _tvSeasonRowExtent = 0;

  TvListReveal get _tvRevealSafe {
    if (_tvReveal != null) return _tvReveal!;
    _tvReveal = TvListReveal.offsets(
      controller: _scroll,
      offsetOf: _tvOffsetOf,
    );
    return _tvReveal!;
  }

  Future<void> _revealIndex(int index) async {
    if (widget.item.kind == CatalogKind.series) {
      await _tvRevealSafe.revealIndex(index);
      return;
    }
    final context = _versionKeys[_tvIds[index]]?.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(context, alignment: 0.5);
    }
  }

  /// 逻辑索引（仅可播放条目）到滚动内容的偏移：按行高表累计。
  double _tvOffsetOf(int index) {
    var offset = 0.0;
    var logical = 0;
    for (final row in _tvRows) {
      if (row is _SeasonHeadingRow) {
        offset += _tvSeasonRowExtent;
      } else {
        if (logical >= index) break;
        offset += _tvEpisodeRowExtent;
        logical++;
      }
    }
    return offset;
  }

  /// itemIds 与偏移表基于同一份行数据；条目变化时重建。
  List<_EpisodeListRow> get _tvRows {
    final item = widget.item;
    return item.kind == CatalogKind.series
        ? _episodeRows(item)
        : const <_EpisodeListRow>[];
  }

  List<String> get _tvIds {
    var ids = _tvItemIds;
    if (ids == null) {
      ids = widget.item.kind == CatalogKind.movie
          ? [for (final version in widget.item.versions) version.mediaId]
          : [
              for (final row in _tvRows)
                if (row is _EpisodeItemRow) row.episode.id,
            ];
      _tvItemIds = ids;
    }
    return ids;
  }

  @override
  void didUpdateWidget(CatalogDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 作品数据变化后重建 id 表与偏移表。
    if (oldWidget.item != widget.item) {
      _tvItemIds = null;
      final ids = widget.item.versions
          .map((version) => version.mediaId)
          .toSet();
      _versionKeys.removeWhere((id, _) => !ids.contains(id));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final episodeRows = _tvRows;
    final isTelevision = widget.television;
    if (isTelevision) {
      _tvEpisodeRowExtent = CatalogEpisodeTile.televisionExtent(context);
      final style = Theme.of(context).textTheme.bodyMedium!;
      _tvSeasonRowExtent =
          MediaQuery.textScalerOf(context).scale(style.fontSize!) *
              (style.height ?? 1.5) +
          LumaSpacing.lg +
          LumaSpacing.sm;
    }
    final scrollBody = Theme(
      data: isTelevision ? Theme.of(context) : catalogDetailTheme(context),
      child: CustomScrollView(
        controller: _scroll,
        cacheExtent: LumaLayout.scrollCacheExtent,
        slivers: [
          SliverToBoxAdapter(
            child: CatalogDetailHero(
              item: widget.item,
              heroTag: widget.heroTag,
              loadBackdrop: widget.loadDetailArtwork,
              favorite: widget.favorite,
              savingFavorite: widget.savingFavorite,
              onPlay: widget.onPlay,
              onPlayFromStart: widget.onPlayFromStart,
              onToggleFavorite: widget.onToggleFavorite,
              television: isTelevision,
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isTelevision
                      ? LumaTvLayout.contentMaxWidth
                      : LumaLayout.detailMaxWidth,
                ),
                child: Padding(
                  padding: LumaLayout.pagePadding(
                    top: 0,
                    bottom: widget.item.kind == CatalogKind.series
                        ? 0
                        : LumaLayout.pagePaddingBottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.item.overview.isNotEmpty) ...[
                        // TV：简介与演职员长区域可聚焦滚动；到边界移出焦点。
                        _longContent(
                          context,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const CatalogSectionHeading(title: '简介'),
                              const SizedBox(height: LumaSpacing.sm),
                              Text(
                                widget.item.overview,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: isTelevision
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onSurface
                                          : CatalogDetailPalette.text,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.1,
                                    ),
                              ),
                              if (widget.item.countries.isNotEmpty ||
                                  widget.item.certification.isNotEmpty) ...[
                                const SizedBox(height: LumaSpacing.md),
                                Text(
                                  [
                                    ...widget.item.countries.map(
                                      (country) => country.name,
                                    ),
                                    if (widget.item.certification.isNotEmpty)
                                      widget.item.certification,
                                  ].join(' · '),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: isTelevision
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant
                                            : CatalogDetailPalette.muted,
                                      ),
                                ),
                              ],
                              const SizedBox(height: LumaSpacing.xl),
                              if (widget.item.credits.isNotEmpty) ...[
                                const CatalogSectionHeading(title: '演职员'),
                                const SizedBox(height: LumaSpacing.md),
                                CatalogCreditStrip(
                                  credits: widget.item.credits,
                                  television: isTelevision,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: LumaSpacing.xl),
                      ] else if (widget.item.credits.isNotEmpty) ...[
                        _longContent(
                          context,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const CatalogSectionHeading(title: '演职员'),
                              const SizedBox(height: LumaSpacing.md),
                              CatalogCreditStrip(
                                credits: widget.item.credits,
                                television: isTelevision,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: LumaSpacing.xl),
                      ],
                      if (widget.item.kind == CatalogKind.movie &&
                          widget.item.versions.isNotEmpty) ...[
                        CatalogSectionHeading(
                          title: '本库其他版本',
                          trailing: '${widget.item.versions.length} 个可播放版本',
                        ),
                        const SizedBox(height: LumaSpacing.sm),
                        ...widget.item.versions.map(
                          (version) => CatalogVersionTile(
                            key: isTelevision
                                ? _versionKeys.putIfAbsent(
                                    version.mediaId,
                                    () => GlobalKey(),
                                  )
                                : ValueKey(version.mediaId),
                            version: version,
                            onPlay: () => widget.onPlay(version.mediaId),
                            focusId: isTelevision ? version.mediaId : null,
                            focusBorderWidth: isTelevision ? 3 : 2,
                          ),
                        ),
                        const SizedBox(height: LumaSpacing.lg),
                      ],
                      if (widget.item.kind == CatalogKind.series) ...[
                        CatalogSectionHeading(
                          title: '选集',
                          trailing: '${widget.item.episodeCount} 集',
                        ),
                        const SizedBox(height: LumaSpacing.md),
                      ],
                      if (widget.item.kind != CatalogKind.series &&
                          widget.item.metadataStatus.isNotEmpty &&
                          widget.item.metadataStatus != 'ready') ...[
                        const SizedBox(height: LumaSpacing.md),
                        CatalogMetadataStatus(
                          status: widget.item.metadataStatus,
                        ),
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
                final maxWidth = isTelevision
                    ? LumaTvLayout.contentMaxWidth
                    : LumaLayout.detailMaxWidth;
                final outside =
                    ((constraints.crossAxisExtent - maxWidth).clamp(
                      0,
                      double.infinity,
                    )) /
                    2;
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    outside + LumaLayout.pagePaddingH,
                    0,
                    outside + LumaLayout.pagePaddingH,
                    widget.item.metadataStatus.isEmpty ||
                            widget.item.metadataStatus == 'ready'
                        ? LumaLayout.pagePaddingBottom
                        : 0,
                  ),
                  sliver: SliverList.builder(
                    itemCount: episodeRows.length,
                    itemBuilder: (context, index) =>
                        switch (episodeRows[index]) {
                          _SeasonHeadingRow(:final label) =>
                            isTelevision
                                ? SizedBox(
                                    height: _tvSeasonRowExtent,
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Padding(
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
                                    ),
                                  )
                                : Padding(
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
                          _EpisodeItemRow(:final episode) =>
                            isTelevision
                                ? SizedBox(
                                    height: _tvEpisodeRowExtent,
                                    child: CatalogEpisodeTile(
                                      key: ValueKey(episode.id),
                                      episode: episode,
                                      onTap: () =>
                                          widget.onPlay(episode.mediaId),
                                      focusId: episode.id,
                                      focusBorderWidth:
                                          LumaTvLayout.focusStroke,
                                      onFocusChange: (focused) {
                                        if (focused) {
                                          final logical = _tvIds.indexOf(
                                            episode.id,
                                          );
                                          if (logical >= 0) {
                                            _tvRevealSafe.track(logical);
                                          }
                                        }
                                      },
                                    ),
                                  )
                                : CatalogEpisodeTile(
                                    key: ValueKey(episode.id),
                                    episode: episode,
                                    onTap: () => widget.onPlay(episode.mediaId),
                                  ),
                        },
                  ),
                );
              },
            ),
          if (widget.item.kind == CatalogKind.series &&
              widget.item.metadataStatus.isNotEmpty &&
              widget.item.metadataStatus != 'ready')
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: LumaLayout.detailMaxWidth,
                  ),
                  child: Padding(
                    padding: LumaLayout.pagePadding(top: LumaSpacing.md),
                    child: CatalogMetadataStatus(
                      status: widget.item.metadataStatus,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (!isTelevision) return scrollBody;
    // TV 外层集合管理版本/选集的方向移动与离屏滚动交接；纵向单列。
    return TvFocusCollection(
      itemIds: _tvIds,
      axis: Axis.vertical,
      columns: 1,
      revealIndex: _revealIndex,
      child: scrollBody,
    );
  }

  /// TV 纯文字长区域的可聚焦滚动容器；普通端原样返回。
  Widget _longContent(BuildContext context, Widget child) {
    if (!widget.television) return child;
    return TvScrollableDetailRegion(child: child);
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
