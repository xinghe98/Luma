import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/controllers/media_controller.dart';
import '../../app/route_transition.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
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
  /// 构建固定类型媒体库，并在路由动画结束后按 [pageSize] 启动远程分页。
  const LibraryPage({
    super.key,
    required this.type,
    required this.onOpenMedia,
    required this.onOpenSearch,
    this.onLongPressMedia,
    this.fixedLibraryKind,
    this.embedded = false,
    this.title,
    this.initialItems = const [],
    this.pageSize = 48,
  }) : assert(pageSize >= 1 && pageSize <= 100);

  final MediaType type;
  final MediaOpenCallback onOpenMedia;
  final VoidCallback onOpenSearch;
  final String? fixedLibraryKind;
  final String? title;

  /// 上一级列表已加载的条目，会在远程刷新完成前作为此页的稳定首帧内容。
  final List<MediaItem> initialItems;

  /// 单次远程分页条数；进入页面时会等路由动画结束后再请求第一页。
  final int pageSize;

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
    if (_controller != null) return;
    final media = AppScope.of(context).media;
    final controller = LibraryController(
      fixedType: widget.type,
      fixedLibraryKind: widget.fixedLibraryKind,
      media: media,
      initialItems: widget.initialItems,
      pageSize: widget.pageSize,
    );
    _controller = controller;
    unawaited(controller.ensureLoadedAfter(waitForRouteTransition(context)));
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
    if (controller == null ||
        !controller.hasMore ||
        controller.isLoadingMore ||
        controller.hasLoadMoreError) {
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 720) {
      controller.loadMore();
    }
  }

  /// 构建媒体库内容，并在筛选生效时保留清除筛选入口。
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
                  if (controller.hasExtraFilters)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        LumaLayout.pagePaddingH,
                        LumaSpacing.xs,
                        LumaLayout.pagePaddingH,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: controller.clearFilters,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('清除筛选'),
                          ),
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
                    if (loadState == LoadState.error)
                      SliverToBoxAdapter(
                        child: ErrorState(
                          compact: true,
                          title: '媒体库刷新失败',
                          message: '当前仍显示相同筛选条件下的上次结果。',
                          retryLabel: '重新刷新',
                          onRetry: controller.refresh,
                        ),
                      ),
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
                    if (controller.hasLoadMoreError)
                      SliverToBoxAdapter(
                        child: ErrorState(
                          compact: true,
                          title: '下一页加载失败',
                          message: '已加载的项目不会丢失，可以继续重试。',
                          retryLabel: '重试下一页',
                          onRetry: controller.loadMore,
                        ),
                      )
                    else if (controller.isLoadingMore)
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
