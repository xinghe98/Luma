import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/route_transition.dart';
import '../../core/theme.dart';
import '../../data/models/api_catalog.dart';
import '../../shared/interaction/tv_focus_collection.dart';
import '../../shared/interaction/tv_key_bindings.dart';
import '../../shared/layout/tv_content_frame.dart';
import '../../shared/media/media_card.dart';
import '../../shared/media/tv_media_grid.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import 'catalog_controller.dart';
import 'widgets/catalog_card.dart';
import 'widgets/tv_catalog_header.dart';

/// “查看全部”进入的完整作品列表，保留原有海报网格、刷新与错误状态。
/// TV 使用固定行高海报网格与逐项焦点；触控端保持既有网格与下拉刷新。
class CatalogCollectionPage extends StatefulWidget {
  const CatalogCollectionPage({
    super.key,
    required this.kind,
    required this.initialItems,
    required this.onOpenCatalog,
    required this.onOpenSearch,
  });

  final CatalogKind kind;
  final List<CatalogItem> initialItems;
  final CatalogOpenCallback onOpenCatalog;
  final VoidCallback onOpenSearch;

  @override
  State<CatalogCollectionPage> createState() => _CatalogCollectionPageState();
}

class _CatalogCollectionPageState extends State<CatalogCollectionPage> {
  final _bodyKey = GlobalKey<CatalogCollectionBodyState>();

  @override
  Widget build(BuildContext context) {
    final isTelevision = AppScope.of(context).deviceProfile.isTelevision;
    final body = CatalogCollectionBody(
      key: _bodyKey,
      kind: widget.kind,
      initialItems: widget.initialItems,
      onOpenCatalog: widget.onOpenCatalog,
    );
    if (isTelevision) {
      return TvKeyBindings(
        child: TvContentFrame(
          child: Scaffold(
            body: Column(
              children: [
                TvCatalogCollectionHeader(
                  title: widget.kind == CatalogKind.movie ? '电影' : '电视剧',
                  onSearch: widget.onOpenSearch,
                  onRefresh: () => _bodyKey.currentState?.refresh(),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      );
    }
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(widget.kind == CatalogKind.movie ? '电影' : '电视剧'),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: widget.onOpenSearch,
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: body,
    );
    return scaffold;
  }
}

class CatalogCollectionBody extends StatefulWidget {
  const CatalogCollectionBody({
    super.key,
    required this.kind,
    required this.initialItems,
    required this.onOpenCatalog,
  });

  final CatalogKind kind;
  final List<CatalogItem> initialItems;
  final CatalogOpenCallback onOpenCatalog;

  @override
  State<CatalogCollectionBody> createState() => CatalogCollectionBodyState();
}

class CatalogCollectionBodyState extends State<CatalogCollectionBody>
    with AutomaticKeepAliveClientMixin<CatalogCollectionBody> {
  CatalogController? _controller;
  bool _entrySettled = false;
  final _scroll = ScrollController();
  TvGridReveal? _tvReveal;
  List<String>? _tvItemIds;
  Map<String, int> _tvItemIndices = const {};

  /// TV 海报网格几何：海报 2:3 加标题与来源行（TV 字号）。
  _TvPosterGridMetrics get _posterMetrics =>
      _TvPosterGridMetrics(MediaCard.textDetailsHeight(context, titleLines: 1));

  @override
  bool get wantKeepAlive => true;

  /// 供集合页 AppBar 的刷新按钮调用既有加载逻辑。
  void refresh() {
    unawaited(_controller?.load());
  }

  TvGridReveal get _tvRevealSafe =>
      _tvReveal ??= TvGridReveal(controller: _scroll, metrics: _posterMetrics);

  // 集合以列表同一性判断数据变化；控制器通知后重建 id 表。
  void _invalidateTvIds() => _tvItemIds = null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final controller = CatalogController(
      AppScope.of(context).catalog,
      kind: widget.kind,
      initialItems: widget.initialItems,
    );
    _controller = controller;
    controller.addListener(_invalidateTvIds);
    final entryGate = waitForRouteTransition(context);
    unawaited(controller.ensureLoadedAfter(entryGate));
    unawaited(_restoreScrollCacheAfter(entryGate));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller
      ?..removeListener(_invalidateTvIds)
      ..dispose();
    super.dispose();
  }

  List<String> get _tvIds {
    var ids = _tvItemIds;
    final items = _controller?.items ?? widget.initialItems;
    if (ids == null) {
      ids = [for (final item in items) item.id];
      _tvItemIds = ids;
      _tvItemIndices = {
        for (var index = 0; index < ids.length; index++) ids[index]: index,
      };
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isTelevision = AppScope.of(context).deviceProfile.isTelevision;
    return ListenableBuilder(
      listenable: _controller!,
      builder: (context, _) {
        final controller = _controller!;
        final scrollBody = CustomScrollView(
          key: PageStorageKey('catalog-scroll-${widget.kind.name}'),
          controller: _scroll,
          cacheExtent: _entrySettled ? LumaLayout.scrollCacheExtent : 0,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (controller.state == CatalogLoadState.loading &&
                controller.items.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  LumaLayout.pagePaddingH,
                  LumaSpacing.lg,
                  LumaLayout.pagePaddingH,
                  LumaSpacing.xl,
                ),
                sliver: isTelevision
                    ? SliverLayoutBuilder(
                        builder: (context, constraints) => SliverGrid.builder(
                          itemCount: 10,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _posterMetrics.columnsFor(
                                  constraints.crossAxisExtent,
                                ),
                                crossAxisSpacing: LumaTvLayout.cardSpacing,
                                mainAxisSpacing: LumaTvLayout.cardSpacing,
                                childAspectRatio: _posterMetrics
                                    .cellAspectRatio(
                                      constraints.crossAxisExtent,
                                    ),
                              ),
                          itemBuilder: (_, _) => const Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: SkeletonBox(
                                  height: double.infinity,
                                  radius: LumaRadii.large,
                                ),
                              ),
                              SizedBox(height: 12),
                              SkeletonBox(height: 18),
                              SizedBox(height: 24),
                            ],
                          ),
                        ),
                      )
                    : const SliverToBoxAdapter(
                        child: PosterGridSkeleton(items: 10),
                      ),
              )
            else if (controller.state == CatalogLoadState.error &&
                controller.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(onRetry: controller.load),
              )
            else if (controller.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: widget.kind == CatalogKind.movie
                      ? Icons.movie_creation_outlined
                      : Icons.video_collection_outlined,
                  title: widget.kind == CatalogKind.movie
                      ? '还没有识别到电影'
                      : '还没有识别到电视剧',
                  message: '在设置中把媒体源标记为对应类型，然后重新扫描。',
                ),
              )
            else ...[
              if (controller.state == CatalogLoadState.loading)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (isTelevision && controller.state == CatalogLoadState.error)
                SliverToBoxAdapter(
                  child: ErrorState(
                    compact: true,
                    title: '刷新失败',
                    message: '仍可浏览已加载的作品。',
                    retryLabel: '重新刷新',
                    onRetry: controller.load,
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  LumaLayout.pagePaddingH,
                  LumaSpacing.lg,
                  LumaLayout.pagePaddingH,
                  LumaSpacing.xl,
                ),
                sliver: isTelevision
                    ? _buildTvPosterGrid(controller)
                    : SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final columns = LumaLayout.posterColumns(
                            constraints.crossAxisExtent,
                          );
                          final cellWidth =
                              (constraints.crossAxisExtent -
                                  LumaSpacing.md * (columns - 1)) /
                              columns;
                          return SliverGrid.builder(
                            itemCount: controller.items.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: LumaSpacing.md,
                                  mainAxisSpacing: LumaSpacing.lg,
                                  mainAxisExtent:
                                      cellWidth * 1.5 +
                                      LumaSpacing.xs +
                                      CatalogCard.textDetailsHeight(context),
                                ),
                            itemBuilder: (context, index) {
                              final item = controller.items[index];
                              final heroTag = CatalogCard.heroTagFor(item);
                              return RepaintBoundary(
                                child: CatalogCard(
                                  item: item,
                                  heroTag: heroTag,
                                  onTap: () => widget.onOpenCatalog(
                                    item,
                                    heroTag: heroTag,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ],
        );
        if (!isTelevision) {
          return RefreshIndicator(
            onRefresh: controller.load,
            child: scrollBody,
          );
        }
        // TV 外层集合承担海报网格的方向移动与离屏滚动交接。
        return LayoutBuilder(
          builder: (context, constraints) => TvFocusCollection(
            itemIds: _tvIds,
            axis: Axis.vertical,
            columns: _posterMetrics.columnsFor(
              constraints.maxWidth - 2 * LumaLayout.pagePaddingH,
            ),
            revealIndex: _tvRevealSafe.revealIndex,
            child: scrollBody,
          ),
        );
      },
    );
  }

  /// TV 海报网格：固定行高保证上下导航可预测，卡片注册进外层集合。
  Widget _buildTvPosterGrid(CatalogController controller) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final reveal = _tvRevealSafe;
        final metrics = _posterMetrics;
        reveal.metrics = metrics;
        return SliverGrid.builder(
          itemCount: controller.items.length,
          findChildIndexCallback: (key) =>
              key is ValueKey<String> ? _tvItemIndices[key.value] : null,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metrics.columnsFor(width),
            crossAxisSpacing: LumaTvLayout.cardSpacing,
            mainAxisSpacing: LumaTvLayout.cardSpacing,
            childAspectRatio: metrics.cellAspectRatio(width),
          ),
          itemBuilder: (context, index) {
            final item = controller.items[index];
            return RepaintBoundary(
              key: ValueKey(item.id),
              child: CatalogCard(
                item: item,
                // TV 不使用 Hero；路由侧同样不携带标签。
                focusId: item.id,
                focusBorderWidth: LumaTvLayout.focusStroke,
                onTap: () => widget.onOpenCatalog(item),
                onFocusChange: (focused) {
                  if (focused) {
                    // 海报网格按海报行高追踪；reveal 偏移用同一几何计算。
                    reveal.track(index, width);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  /// 入场动画完成后恢复屏外缓存，避免路由或 Hero 过渡期间解码额外海报。
  Future<void> _restoreScrollCacheAfter(Future<void> gate) async {
    await gate;
    if (!mounted || _entrySettled) return;
    setState(() => _entrySettled = true);
  }
}

/// TV 海报网格几何：与媒体网格共用局部宽度来源，行高按海报 2:3 计算。
class _TvPosterGridMetrics implements TvGridMetrics {
  const _TvPosterGridMetrics(this._detailsHeight);

  final double _detailsHeight;

  @override
  int columnsFor(double width) => LumaTvLayout.gridColumns(
    width,
    minItemWidth: LumaTvLayout.posterMinWidth,
  );

  @override
  double rowExtentFor(double width) {
    final columns = columnsFor(width);
    final cellWidth =
        (width - LumaTvLayout.cardSpacing * (columns - 1)) / columns;
    return cellWidth * 1.5 + _detailsHeight + LumaTvLayout.cardSpacing;
  }

  double cellAspectRatio(double width) {
    final columns = columnsFor(width);
    final cellWidth =
        (width - LumaTvLayout.cardSpacing * (columns - 1)) / columns;
    return cellWidth / (cellWidth * 1.5 + _detailsHeight);
  }
}
