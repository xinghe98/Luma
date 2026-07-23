import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/controllers/media_controller.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/media_types.dart';
import '../../shared/media/masonry_media_sliver.dart';
import '../../shared/media/media_actions.dart';
import '../../shared/media/responsive_media_grid.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import 'dialogs/library_filter_sheet.dart';
import 'library_controller.dart';

/// 固定类型的媒体库页：底部导航拆分为影音库与图片库两个入口。
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.type,
    required this.onOpenMedia,
    required this.onOpenSearch,
    this.onLongPressMedia,
    this.fixedLibraryKind,
    this.embedded = false,
    this.title,
  });

  final MediaType type;
  final MediaOpenCallback onOpenMedia;
  final VoidCallback onOpenSearch;
  final String? fixedLibraryKind;
  final String? title;

  /// 嵌入影视库分页时仅渲染内容和局部工具栏，避免嵌套 Scaffold/AppBar。
  final bool embedded;

  /// 图片库长按进详情等；影音库可不传。
  final MediaOpenCallback? onLongPressMedia;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with AutomaticKeepAliveClientMixin<LibraryPage> {
  LibraryController? _controller;
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = AppScope.of(context).media;
    _controller ??= LibraryController(
      fixedType: widget.type,
      fixedLibraryKind: widget.fixedLibraryKind,
      media: media,
    );
    _controller!.ensureLoaded();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onScroll() {
    final controller = _controller;
    if (controller == null || !controller.hasMore || controller.isLoadingMore) {
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 720) {
      controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final media = AppScope.of(context).media;
    final controller = _controller!;
    final isVideo = widget.type == MediaType.video;
    // 只监听库控制器；收藏/进度变更由 LibraryController 选择性转发。
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.visibleItems();
        final loadState = controller.loadState;
        final showInitialSkeleton =
            loadState == LoadState.loading && items.isEmpty;
        final body = RefreshIndicator(
          onRefresh: controller.refresh,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LumaLayout.contentMaxWidth,
              ),
              child: CustomScrollView(
                key: PageStorageKey(
                  'library-scroll-${widget.type.name}-${widget.fixedLibraryKind ?? 'all'}',
                ),
                controller: _scroll,
                // 只预构建约半屏内容，控制快速滑动时的并发解码和纹理峰值。
                cacheExtent: LumaLayout.scrollCacheExtent,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (controller.isRefreshing)
                    const SliverToBoxAdapter(
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      LumaLayout.pagePaddingH,
                      LumaSpacing.xs,
                      LumaLayout.pagePaddingH,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Text(
                            controller.hasMore
                                ? '已加载 ${items.length} 个项目'
                                : '${items.length} 个项目',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const Spacer(),
                          if (controller.hasExtraFilters)
                            TextButton.icon(
                              onPressed: controller.clearFilters,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: const Text('清除筛选'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (showInitialSkeleton)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        LumaLayout.pagePaddingH,
                        LumaSpacing.sm,
                        LumaLayout.pagePaddingH,
                        LumaSpacing.xl,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: MediaGridSkeleton(items: 8),
                      ),
                    )
                  else if (loadState == LoadState.error && items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: ErrorState(onRetry: controller.refresh),
                    )
                  else if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        title: widget.fixedLibraryKind == 'personal'
                            ? '还没有个人视频'
                            : isVideo
                            ? '影音库还没有内容'
                            : '图片库还没有内容',
                        message: '尝试清除筛选条件，或等待服务器扫描完成。',
                        icon: Icons.filter_alt_off_outlined,
                        action: OutlinedButton(
                          onPressed: () =>
                              controller.clearFilters(includeType: true),
                          child: const Text('清除筛选条件'),
                        ),
                      ),
                    )
                  else ...[
                    if (isVideo)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          LumaLayout.pagePaddingH,
                          LumaSpacing.sm,
                          LumaLayout.pagePaddingH,
                          LumaSpacing.xs,
                        ),
                        sliver: ResponsiveMediaSliverGrid(
                          items: items,
                          heroTagPrefix: 'videos',
                          onTap: widget.onOpenMedia,
                          onFavorite: (item) =>
                              context.toggleFavoriteWithFeedback(media, item),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          LumaSpacing.sm,
                          LumaSpacing.xs,
                          LumaSpacing.sm,
                          LumaSpacing.xs,
                        ),
                        sliver: MasonryMediaSliver(
                          items: items,
                          onTap: widget.onOpenMedia,
                          onLongPress: widget.onLongPressMedia,
                          onFavorite: (item) =>
                              context.toggleFavoriteWithFeedback(media, item),
                        ),
                      ),
                    if (controller.isLoadingMore || controller.hasMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            LumaLayout.pagePaddingH,
                            LumaSpacing.xs,
                            LumaLayout.pagePaddingH,
                            LumaSpacing.xl,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      )
                    else
                      const SliverToBoxAdapter(
                        child: SizedBox(height: LumaSpacing.xl),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
        if (widget.embedded) {
          return Column(
            children: [
              SizedBox(
                height: LumaLayout.buttonHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _actions(),
                ),
              ),
              Expanded(child: body),
            ],
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: ScrollToTopAppBarTitle(
              title: widget.title ?? (isVideo ? '影音库' : '图片库'),
              controller: _scroll,
            ),
            actions: _actions(),
          ),
          body: body,
        );
      },
    );
  }

  List<Widget> _actions() => [
    if (!widget.embedded)
      IconButton(
        tooltip: '搜索',
        onPressed: widget.onOpenSearch,
        icon: const Icon(Icons.search_rounded),
      ),
    if (widget.type == MediaType.video)
      IconButton(
        tooltip: '筛选',
        onPressed: _openFilters,
        icon: Badge(
          isLabelVisible: _controller?.hasExtraFilters ?? false,
          child: const Icon(Icons.tune_rounded),
        ),
      )
    else
      IconButton(
        tooltip: _controller?.favoritesOnly ?? false ? '显示全部图片' : '仅显示收藏',
        onPressed: () => _controller?.applyFilters(
          LibraryFilters(favoritesOnly: !(_controller?.favoritesOnly ?? false)),
        ),
        icon: Badge(
          isLabelVisible: _controller?.favoritesOnly ?? false,
          child: Icon(
            _controller?.favoritesOnly ?? false
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
        ),
      ),
    PopupMenuButton<MediaSort>(
      tooltip: '排序',
      initialValue: _controller?.sort ?? MediaSort.newest,
      onSelected: _controller?.setSort,
      itemBuilder: (_) => [
        const PopupMenuItem(value: MediaSort.newest, child: Text('最近添加')),
        const PopupMenuItem(value: MediaSort.title, child: Text('标题名称')),
        if (widget.type == MediaType.video)
          const PopupMenuItem(value: MediaSort.duration, child: Text('视频时长')),
      ],
    ),
  ];

  Future<void> _openFilters() async {
    final controller = _controller;
    if (controller == null) return;
    final result = await showLibraryFilterSheet(
      context,
      controller.filters,
      showWatchStatus: widget.type == MediaType.video,
    );
    if (result != null) controller.applyFilters(result);
  }
}
