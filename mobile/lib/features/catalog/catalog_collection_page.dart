import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/route_transition.dart';
import '../../core/theme.dart';
import '../../data/models/api_catalog.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import 'catalog_controller.dart';
import 'widgets/catalog_card.dart';

/// “查看全部”进入的完整作品列表，保留原有海报网格、刷新与错误状态。
class CatalogCollectionPage extends StatelessWidget {
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(kind == CatalogKind.movie ? '电影' : '电视剧'),
      actions: [
        IconButton(
          tooltip: '搜索',
          onPressed: onOpenSearch,
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    ),
    body: CatalogCollectionBody(
      kind: kind,
      initialItems: initialItems,
      onOpenCatalog: onOpenCatalog,
    ),
  );
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
  State<CatalogCollectionBody> createState() => _CatalogCollectionBodyState();
}

class _CatalogCollectionBodyState extends State<CatalogCollectionBody>
    with AutomaticKeepAliveClientMixin<CatalogCollectionBody> {
  CatalogController? _controller;

  @override
  bool get wantKeepAlive => true;

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
    unawaited(controller.ensureLoadedAfter(waitForRouteTransition(context)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: _controller!,
      builder: (context, _) {
        final controller = _controller!;
        return RefreshIndicator(
          onRefresh: controller.load,
          child: CustomScrollView(
            key: PageStorageKey('catalog-scroll-${widget.kind.name}'),
            cacheExtent: LumaLayout.scrollCacheExtent,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (controller.state == CatalogLoadState.loading &&
                  controller.items.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    LumaLayout.pagePaddingH,
                    LumaSpacing.lg,
                    LumaLayout.pagePaddingH,
                    LumaSpacing.xl,
                  ),
                  sliver: SliverToBoxAdapter(
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    LumaLayout.pagePaddingH,
                    LumaSpacing.lg,
                    LumaLayout.pagePaddingH,
                    LumaSpacing.xl,
                  ),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final columns = _posterColumns(
                        constraints.crossAxisExtent,
                      );
                      return SliverGrid.builder(
                        itemCount: controller.items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: LumaSpacing.md,
                          mainAxisSpacing: LumaSpacing.lg,
                          childAspectRatio: 0.59,
                        ),
                        itemBuilder: (context, index) {
                          final item = controller.items[index];
                          final heroTag = CatalogCard.heroTagFor(item);
                          return RepaintBoundary(
                            child: CatalogCard(
                              item: item,
                              heroTag: heroTag,
                              onTap: () =>
                                  widget.onOpenCatalog(item, heroTag: heroTag),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

int _posterColumns(double width) {
  if (width < 360) return 2;
  if (width < 620) return 3;
  if (width < 900) return 5;
  if (width < 1240) return 6;
  return 8;
}
