import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../data/models/api_catalog.dart';
import '../../data/models/media_types.dart';
import '../../shared/media/media_actions.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import '../library/library_page.dart';
import 'catalog_controller.dart';
import 'widgets/catalog_card.dart';

/// 影视库统一承载电影、电视剧和个人视频，切换时保留各自滚动位置与数据。
class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.onOpenCatalog,
    required this.onOpenPersonalMedia,
    required this.onOpenSearch,
  });

  final ValueChanged<CatalogItem> onOpenCatalog;
  final MediaOpenCallback onOpenPersonalMedia;
  final VoidCallback onOpenSearch;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage>
    with
        AutomaticKeepAliveClientMixin<CatalogPage>,
        SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final Map<int, Widget> _pages = {};
  final Map<int, BuildContext> _scrollContexts = {};
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _pages.putIfAbsent(_selectedIndex, () => _buildPage(_selectedIndex));
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
        bottom: TabBar(
          controller: _tabs,
          onTap: (index) {
            if (_selectedIndex == index) return;
            setState(() => _selectedIndex = index);
          },
          tabs: const [
            Tab(text: '电影', icon: Icon(Icons.movie_outlined)),
            Tab(text: '电视剧', icon: Icon(Icons.tv_outlined)),
            Tab(text: '个人视频', icon: Icon(Icons.video_library_outlined)),
          ],
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _rememberScrollContext,
        child: IndexedStack(
          index: _selectedIndex,
          children: List.generate(
            3,
            (index) => TickerMode(
              enabled: index == _selectedIndex,
              child: _pages[index] ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(int index) => switch (index) {
    0 => _CatalogSection(
      kind: CatalogKind.movie,
      onOpenCatalog: widget.onOpenCatalog,
    ),
    1 => _CatalogSection(
      kind: CatalogKind.series,
      onOpenCatalog: widget.onOpenCatalog,
    ),
    _ => LibraryPage(
      type: MediaType.video,
      fixedLibraryKind: 'personal',
      embedded: true,
      onOpenMedia: widget.onOpenPersonalMedia,
      onOpenSearch: widget.onOpenSearch,
    ),
  };

  // 每个 Tab 各自保留滚动位置，标题双击仅回到当前可见列表的起点。
  bool _rememberScrollContext(ScrollNotification notification) {
    if (notification.depth == 0 && notification.context != null) {
      _scrollContexts[_selectedIndex] = notification.context!;
    }
    return false;
  }

  void _scrollToTop() {
    final context = _scrollContexts[_selectedIndex];
    final scrollable = context == null ? null : Scrollable.maybeOf(context);
    final position = scrollable?.position;
    if (position == null || position.pixels <= position.minScrollExtent) return;
    position.animateTo(
      position.minScrollExtent,
      duration: LumaMotion.normal,
      curve: LumaMotion.standard,
    );
  }
}

class _CatalogSection extends StatefulWidget {
  const _CatalogSection({required this.kind, required this.onOpenCatalog});

  final CatalogKind kind;
  final ValueChanged<CatalogItem> onOpenCatalog;

  @override
  State<_CatalogSection> createState() => _CatalogSectionState();
}

class _CatalogSectionState extends State<_CatalogSection>
    with AutomaticKeepAliveClientMixin<_CatalogSection> {
  CatalogController? _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= CatalogController(
      AppScope.of(context).catalog,
      kind: widget.kind,
    );
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
            cacheExtent: 360,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (controller.state == CatalogLoadState.loading)
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
              else if (controller.state == CatalogLoadState.error)
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
              else
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
          ),
        );
      },
    );
  }

  static int _posterColumns(double width) {
    if (width < 360) return 2;
    if (width < 620) return 3;
    if (width < 900) return 5;
    if (width < 1240) return 6;
    return 8;
  }
}
