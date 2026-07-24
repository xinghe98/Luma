import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/controllers/media_controller.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/api_catalog.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import '../../shared/layout/section_header.dart';
import '../../shared/media/media_actions.dart';
import '../../shared/media/responsive_media_grid.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import '../library/library_controller.dart';
import 'catalog_controller.dart';
import 'widgets/catalog_card.dart';

/// 影视库总览按内容分区，让用户先浏览内容，再按需进入完整分类列表。
class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.onOpenCatalog,
    required this.onOpenPersonalMedia,
    required this.onOpenSearch,
    required this.onOpenMovies,
    required this.onOpenSeries,
    required this.onOpenPersonalVideos,
  });

  final ValueChanged<CatalogItem> onOpenCatalog;
  final MediaOpenCallback onOpenPersonalMedia;
  final VoidCallback onOpenSearch;
  final ValueChanged<List<CatalogItem>> onOpenMovies;
  final ValueChanged<List<CatalogItem>> onOpenSeries;
  /// 打开完整个人视频库，并携带当前分区已经加载的条目作为首帧数据。
  final ValueChanged<List<MediaItem>> onOpenPersonalVideos;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage>
    with AutomaticKeepAliveClientMixin<CatalogPage> {
  CatalogController? _movies;
  CatalogController? _series;
  LibraryController? _personalVideos;
  final _scroll = ScrollController();
  final _seriesSectionKey = GlobalKey();
  final _personalSectionKey = GlobalKey();
  bool _hasUserScrolled = false;
  bool _loadCheckScheduled = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_movies != null) return;
    final dependencies = AppScope.of(context);
    _movies = CatalogController(dependencies.catalog, kind: CatalogKind.movie);
    _series = CatalogController(dependencies.catalog, kind: CatalogKind.series);
    _personalVideos = LibraryController(
      fixedType: MediaType.video,
      fixedLibraryKind: 'personal',
      media: dependencies.media,
    );
    // 总览首屏只占用一个分类请求，其他分区在用户接近时再拉取。
    _movies!.ensureLoaded();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _movies?.dispose();
    _series?.dispose();
    _personalVideos?.dispose();
    super.dispose();
  }

  Future<void> _refresh() {
    final requests = <Future<void>>[
      if (_movies!.hasStarted) _movies!.load(),
      if (_series!.hasStarted) _series!.load(),
      if (_personalVideos!.hasStarted) _personalVideos!.refresh(),
    ];
    return requests.isEmpty ? Future.value() : Future.wait(requests);
  }

  void _scheduleUpcomingLoadCheck() {
    if (!_hasUserScrolled || _loadCheckScheduled) return;
    _loadCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCheckScheduled = false;
      if (!mounted) return;
      final series = _series!;
      final personal = _personalVideos!;
      if (!series.hasStarted && _isNearViewport(_seriesSectionKey)) {
        series.ensureLoaded();
        return;
      }
      if (!personal.hasStarted && _isNearViewport(_personalSectionKey)) {
        personal.ensureLoaded();
      }
    });
  }

  bool _isNearViewport(GlobalKey sectionKey) {
    final renderObject = sectionKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    // 只在用户滚动后预取。分区顶部进入当前视口下方约四分之一屏时请求，
    // 既避免首屏三路竞争，也不让用户停在空骨架前等待。
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final threshold = MediaQuery.sizeOf(context).height * 1.25;
    return top <= threshold;
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels <= position.minScrollExtent) return;
    position.animateTo(
      position.minScrollExtent,
      duration: LumaMotion.normal,
      curve: LumaMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final movies = _movies!;
    final series = _series!;
    final personalVideos = _personalVideos!;
    return ListenableBuilder(
      listenable: Listenable.merge([movies, series, personalVideos]),
      builder: (context, _) {
        final personalItems = personalVideos.visibleItems();
        final allLoaded =
            movies.hasStarted &&
            series.hasStarted &&
            personalVideos.hasStarted &&
            movies.state == CatalogLoadState.ready &&
            series.state == CatalogLoadState.ready &&
            personalVideos.loadState == LoadState.ready;
        final allEmpty =
            allLoaded &&
            movies.items.isEmpty &&
            series.items.isEmpty &&
            personalItems.isEmpty;
        void openPersonalVideos() =>
            widget.onOpenPersonalVideos(personalItems);
        return Scaffold(
          appBar: AppBar(
            title: ScrollToTopAppBarTitle(
              title: '影视库',
              onScrollToTop: _scrollToTop,
            ),
            actions: [
              IconButton(
                tooltip: '搜索',
                onPressed: widget.onOpenSearch,
                icon: const Icon(Icons.search_rounded),
              ),
            ],
          ),
          body: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification &&
                  notification.scrollDelta != 0) {
                _hasUserScrolled = true;
                _scheduleUpcomingLoadCheck();
              }
              return false;
            },
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                controller: _scroll,
                key: const PageStorageKey('catalog-overview-scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                cacheExtent: LumaLayout.scrollCacheExtent,
                slivers: [
                  if (allEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.video_library_outlined,
                        title: '影视库还没有内容',
                        message: '在设置中添加电影、电视剧或个人视频目录后重新扫描。',
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: _CatalogShelfSection(
                        title: '电影',
                        controller: movies,
                        onOpenCatalog: widget.onOpenCatalog,
                        onOpenAll: widget.onOpenMovies,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: KeyedSubtree(
                        key: _seriesSectionKey,
                        child: _CatalogShelfSection(
                          title: '电视剧',
                          controller: series,
                          onOpenCatalog: widget.onOpenCatalog,
                          onOpenAll: widget.onOpenSeries,
                        ),
                      ),
                    ),
                    if (!personalVideos.hasStarted ||
                        personalVideos.loadState == LoadState.loading)
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _personalSectionKey,
                          child: _CatalogShelfPlaceholder(
                            title: '个人视频',
                            onOpenAll: openPersonalVideos,
                          ),
                        ),
                      )
                    else if (personalVideos.loadState == LoadState.error)
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _personalSectionKey,
                          child: _CatalogSectionIssue(
                            title: '个人视频',
                            onRetry: personalVideos.refresh,
                            onOpenAll: openPersonalVideos,
                          ),
                        ),
                      )
                    else if (personalItems.isEmpty)
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _personalSectionKey,
                          child: _CatalogSectionEmpty(
                            title: '个人视频',
                            onOpenAll: openPersonalVideos,
                          ),
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _personalSectionKey,
                          child: _SectionHeading(
                            title: '个人视频',
                            onOpenAll: openPersonalVideos,
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          LumaLayout.pagePaddingH,
                          LumaSpacing.md,
                          LumaLayout.pagePaddingH,
                          LumaSpacing.xl,
                        ),
                        sliver: ResponsiveMediaSliverGrid(
                          items: personalItems.take(6).toList(growable: false),
                          heroTagPrefix: 'catalog-personal',
                          onTap: widget.onOpenPersonalMedia,
                          onFavorite: (item) =>
                              context.toggleFavoriteWithFeedback(
                                AppScope.of(context).media,
                                item,
                              ),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(
                      child: SizedBox(height: LumaSpacing.xl),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

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
  final ValueChanged<CatalogItem> onOpenCatalog;
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
  final ValueChanged<CatalogItem> onOpenCatalog;

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
    _controller ??= CatalogController(
      AppScope.of(context).catalog,
      kind: widget.kind,
      initialItems: widget.initialItems,
    )..ensureLoaded();
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
                          return RepaintBoundary(
                            child: CatalogCard(
                              item: item,
                              onTap: () => widget.onOpenCatalog(item),
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

class _CatalogShelfSection extends StatelessWidget {
  const _CatalogShelfSection({
    required this.title,
    required this.controller,
    required this.onOpenCatalog,
    required this.onOpenAll,
  });

  final String title;
  final CatalogController controller;
  final ValueChanged<CatalogItem> onOpenCatalog;
  final ValueChanged<List<CatalogItem>> onOpenAll;

  @override
  Widget build(BuildContext context) {
    void openAll() => onOpenAll(controller.items);
    if (controller.state == CatalogLoadState.error) {
      return _CatalogSectionIssue(
        title: title,
        onRetry: controller.load,
        onOpenAll: openAll,
      );
    }
    if (controller.state != CatalogLoadState.ready) {
      return _CatalogShelfPlaceholder(title: title, onOpenAll: openAll);
    }
    if (controller.items.isEmpty) {
      return _CatalogSectionEmpty(title: title, onOpenAll: openAll);
    }
    return _CatalogShelf(
      title: title,
      items: controller.items,
      onOpenCatalog: onOpenCatalog,
      onOpenAll: openAll,
    );
  }
}

class _CatalogShelfPlaceholder extends StatelessWidget {
  const _CatalogShelfPlaceholder({
    required this.title,
    required this.onOpenAll,
  });

  final String title;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        const SizedBox(height: LumaSpacing.md),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: LumaLayout.pagePaddingH),
          child: SizedBox(
            height: 262,
            child: Row(
              children: [
                Expanded(
                  child: SkeletonBox(
                    height: double.infinity,
                    radius: LumaRadii.large,
                  ),
                ),
                SizedBox(width: LumaSpacing.md),
                Expanded(
                  child: SkeletonBox(
                    height: double.infinity,
                    radius: LumaRadii.large,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _CatalogSectionIssue extends StatelessWidget {
  const _CatalogSectionIssue({
    required this.title,
    required this.onRetry,
    required this.onOpenAll,
  });

  final String title;
  final VoidCallback onRetry;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        SizedBox(
          height: 262,
          child: Center(
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('加载失败，轻触重试'),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CatalogSectionEmpty extends StatelessWidget {
  const _CatalogSectionEmpty({required this.title, required this.onOpenAll});

  final String title;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        SizedBox(
          height: 108,
          child: Center(
            child: Text(
              '暂时没有$title',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CatalogShelf extends StatelessWidget {
  const _CatalogShelf({
    required this.title,
    required this.items,
    required this.onOpenCatalog,
    required this.onOpenAll,
  });

  final String title;
  final List<CatalogItem> items;
  final ValueChanged<CatalogItem> onOpenCatalog;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        const SizedBox(height: LumaSpacing.md),
        SizedBox(
          height: 262,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: LumaLayout.pagePaddingH,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: items.length.clamp(0, 12),
            separatorBuilder: (_, _) => const SizedBox(width: LumaSpacing.md),
            itemBuilder: (context, index) => SizedBox(
              width: 138,
              child: CatalogCard(
                item: items[index],
                onTap: () => onOpenCatalog(items[index]),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.onOpenAll});

  final String title;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: LumaLayout.pagePaddingH),
    child: SectionHeader(
      title: title,
      action: TextButton(
        onPressed: onOpenAll,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('查看全部'), Icon(Icons.chevron_right_rounded)],
        ),
      ),
    ),
  );
}

int _posterColumns(double width) {
  if (width < 360) return 2;
  if (width < 620) return 3;
  if (width < 900) return 5;
  if (width < 1240) return 6;
  return 8;
}
