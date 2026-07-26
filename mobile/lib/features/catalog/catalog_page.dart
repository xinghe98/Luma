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
import '../../shared/states/skeleton.dart';
import '../library/library_controller.dart';
import 'catalog_controller.dart';
import 'widgets/catalog_card.dart';

export 'catalog_collection_page.dart';

part 'widgets/catalog_shelf.dart';

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

  final CatalogOpenCallback onOpenCatalog;
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
      pageSize: 6,
    );
    // 电影先发起请求；首帧布局后会按可视范围补齐邻近分区。
    _movies!.ensureLoaded();
    _scheduleUpcomingLoadCheck();
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
    if (_loadCheckScheduled) return;
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
    // 分区顶部进入当前视口下方约四分之一屏时请求，
    // 既避免首屏三路竞争，也不让用户停在空骨架前等待。
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final threshold = MediaQuery.sizeOf(context).height * 1.25;
    return top <= threshold;
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels <= position.minScrollExtent) return;
    position.jumpTo(position.minScrollExtent);
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
        void openPersonalVideos() => widget.onOpenPersonalVideos(
          personalItems.take(6).toList(growable: false),
        );
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
                    if (personalItems.isEmpty &&
                        (!personalVideos.hasStarted ||
                            personalVideos.loadState == LoadState.loading))
                      SliverToBoxAdapter(
                        child: KeyedSubtree(
                          key: _personalSectionKey,
                          child: _CatalogShelfPlaceholder(
                            title: '个人视频',
                            onOpenAll: openPersonalVideos,
                          ),
                        ),
                      )
                    else if (personalItems.isEmpty &&
                        personalVideos.loadState == LoadState.error)
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
                      if (personalVideos.loadState == LoadState.loading)
                        const SliverToBoxAdapter(
                          child: LinearProgressIndicator(minHeight: 2),
                        )
                      else if (personalVideos.loadState == LoadState.error)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: LumaLayout.pagePaddingH,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: personalVideos.refresh,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('刷新失败，当前保留上次内容'),
                              ),
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
