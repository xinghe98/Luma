import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/controllers/media_controller.dart';
import '../../app/route_transition.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import '../../shared/interaction/tv_focus_collection.dart';
import '../../shared/interaction/tv_key_bindings.dart';
import '../../shared/layout/tv_content_frame.dart';
import '../../shared/media/image_gallery_controller.dart';
import '../../shared/media/masonry_media_sliver.dart';
import '../../shared/media/media_actions.dart';
import '../../shared/media/responsive_media_grid.dart';
import '../../shared/media/tv_media_grid.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import '../shell/shell_entry_gate.dart';
import 'dialogs/library_filter_sheet.dart';
import 'library_controller.dart';
import 'widgets/tv_library_header.dart';
import 'widgets/active_filter_bar.dart';
import 'widgets/library_sort_button.dart';

/// 图片库打开全屏预览的入口；由页面构建好翻页会话后调用，
/// 返回时预览已完全关闭，页面负责销毁会话。
typedef ImageGalleryOpenCallback =
    Future<void> Function(ImageGalleryController gallery, {String? heroTag});

/// 固定类型的媒体库页：底部导航拆分为影音库与图片库两个入口。
class LibraryPage extends StatefulWidget {
  /// 构建固定类型媒体库，并在路由动画结束后按 [pageSize] 启动远程分页。
  const LibraryPage({
    super.key,
    required this.type,
    required this.onOpenMedia,
    required this.onOpenSearch,
    this.fixedLibraryKind,
    this.onLongPressMedia,
    this.onOpenImageGallery,
    this.onUploadImages,
    this.embedded = false,
    this.inShell = false,
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

  /// 壳层分支已提供 TV 安全边距，根层个人视频路由则由此页提供。
  final bool inShell;

  /// 图片库长按进详情等；影音库可不传。
  final MediaOpenCallback? onLongPressMedia;

  /// 图片分支专用：传入后点击图片改为建立翻页会话并交给预览，
  /// 其余媒体类型或未提供时仍走 [onOpenMedia]。
  final ImageGalleryOpenCallback? onOpenImageGallery;

  /// 打开本地图片上传；返回 true 时保留现有网格并刷新上传后的内容。
  final Future<bool> Function()? onUploadImages;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with AutomaticKeepAliveClientMixin<LibraryPage> {
  LibraryController? _controller;
  final _scroll = ScrollController();
  bool _entrySettled = false;
  bool _loadMoreCheckScheduled = false;

  /// 预览打开期间暂停网格自动补页，分页只由预览翻页驱动。
  bool _galleryPreviewActive = false;
  bool _uploadPageOpen = false;

  /// TV 网格的滚动基准与稳定 id 表；控制器通知后重建。
  TvGridReveal? _tvReveal;
  List<String>? _tvItemIds;

  TvGridReveal get _tvRevealSafe =>
      _tvReveal ??= TvGridReveal(controller: _scroll);

  void _invalidateTvIds() => _tvItemIds = null;

  List<String> get _tvIds {
    var ids = _tvItemIds;
    final items = _controller?.visibleItems() ?? const <MediaItem>[];
    if (ids == null) {
      ids = [for (final item in items) item.id];
      _tvItemIds = ids;
    }
    return ids;
  }

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
    final dependencies = AppScope.of(context);
    final media = dependencies.media;
    final initialItems = widget.initialItems.isNotEmpty
        ? widget.initialItems
        : dependencies.mediaBranchPrewarmer.photos;
    final controller = LibraryController(
      fixedType: widget.type,
      fixedLibraryKind: widget.fixedLibraryKind,
      media: media,
      initialItems: initialItems,
      pageSize: widget.pageSize,
    );
    _controller = controller;
    controller.addListener(_scheduleLoadMoreCheck);
    controller.addListener(_invalidateTvIds);
    final entryGate = _waitForEntrySettle();
    unawaited(controller.ensureLoadedAfter(entryGate));
    unawaited(_restoreScrollCacheAfter(entryGate));
  }

  @override
  void dispose() {
    // 页面销毁时唤醒仍在等待分页落定的预览续页请求。
    if (_gallerySettled != null && !_gallerySettled!.isCompleted) {
      _gallerySettled!.complete();
    }
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _controller
      ?..removeListener(_scheduleLoadMoreCheck)
      ..removeListener(_invalidateTvIds)
      ..dispose();
    super.dispose();
  }

  void _onScroll() => _maybeLoadMore();

  /// 内容不足以产生滚动量时（如 Windows 最大化首屏），滚动监听不会触发，
  /// 需在布局稳定后主动检查是否仍需追加下一页。
  void _scheduleLoadMoreCheck() {
    if (_loadMoreCheckScheduled) return;
    _loadMoreCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreCheckScheduled = false;
      if (!mounted) return;
      _maybeLoadMore();
    });
  }

  void _maybeLoadMore() {
    final controller = _controller;
    if (_galleryPreviewActive ||
        controller == null ||
        !controller.hasMore ||
        controller.isLoadingMore ||
        controller.hasLoadMoreError) {
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 720) {
      unawaited(controller.loadMore());
    }
  }

  /// 图片库点击：基于当前可见顺序建立翻页会话交给预览；
  /// 打开期间暂停自动补页，会话只按预览翻页追加下一页。
  void _openGallery(MediaItem item, {String? heroTag}) {
    if (_galleryPreviewActive) return;
    final openGallery = widget.onOpenImageGallery;
    final controller = _controller;
    if (openGallery == null || controller == null) {
      widget.onOpenMedia(item, heroTag: heroTag);
      return;
    }
    final items = controller.visibleItems();
    assert(
      items.any((entry) => entry.id == item.id),
      '点击图片必须来自当前可见列表',
    );
    if (items.isEmpty) {
      widget.onOpenMedia(item, heroTag: heroTag);
      return;
    }
    // 首刷未完成或失败时，保留从预览继续加载、重试的入口。
    final hasMore =
        controller.hasMore ||
        controller.loadState != LoadState.ready ||
        controller.isLoadingMore;
    late final ImageGalleryController gallery;
    gallery = ImageGalleryController(
      items: items,
      initialId: item.id,
      hasMore: hasMore,
      loadMore: () => _loadGalleryPage(controller, gallery),
    );
    _galleryPreviewActive = true;
    openGallery(gallery, heroTag: heroTag).whenComplete(() {
      gallery.dispose();
      if (mounted) {
        _galleryPreviewActive = false;
        // 预览期间被抑制的补页需求在关闭后补一次检查。
        _maybeLoadMore();
      }
    });
  }

  /// 为预览拉取下一页：先把来源已加载但会话未见的条目并入，
  /// 再判断来源是否还有后续页；来源分页失败时抛出错误供预览重试。
  Future<ImageGalleryPage> _loadGalleryPage(
    LibraryController controller,
    ImageGalleryController gallery,
  ) async {
    await _waitForLibrarySettled(controller);
    if (!mounted) {
      return const ImageGalleryPage(items: [], hasMore: false);
    }
    if (controller.loadState == LoadState.error) {
      await controller.refresh();
      if (!mounted) {
        return const ImageGalleryPage(items: [], hasMore: false);
      }
      if (controller.loadState == LoadState.error) {
        throw StateError('图片列表加载失败，请重试');
      }
    }
    // 等待期间来源可能已追加过新页：先并入未见条目，能前进就不再请求。
    var unseen = _unseenItems(controller, gallery);
    if (unseen.isNotEmpty) {
      return ImageGalleryPage(items: unseen, hasMore: controller.hasMore);
    }
    if (!controller.hasMore) {
      return const ImageGalleryPage(items: [], hasMore: false);
    }
    await controller.loadMore();
    if (!mounted) {
      return const ImageGalleryPage(items: [], hasMore: false);
    }
    // LibraryController.loadMore 吞掉异常只更新错误标记，
    // 这里转成明确错误，让预览停留在当前图并允许重试。
    if (controller.hasLoadMoreError) {
      throw StateError('下一页加载失败');
    }
    unseen = _unseenItems(controller, gallery);
    return ImageGalleryPage(items: unseen, hasMore: controller.hasMore);
  }

  List<MediaItem> _unseenItems(
    LibraryController controller,
    ImageGalleryController gallery,
  ) => controller
      .visibleItems()
      .where((item) => !gallery.containsId(item.id))
      .toList(growable: false);

  /// 监听直到来源既不在首刷也不在翻页；页面销毁时通过 [_gallerySettled]
  /// 唤醒等待方直接返回，避免悬挂在不再 notify 的控制器上。
  Completer<void>? _gallerySettled;

  Future<void> _waitForLibrarySettled(LibraryController controller) async {
    while (mounted &&
        (controller.loadState == LoadState.loading ||
            controller.isLoadingMore)) {
      final changed = Completer<void>();
      _gallerySettled = changed;
      void listener() {
        if (!changed.isCompleted) changed.complete();
      }

      controller.addListener(listener);
      try {
        await changed.future;
      } finally {
        controller.removeListener(listener);
        if (identical(_gallerySettled, changed)) _gallerySettled = null;
      }
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
        final isTelevision = AppScope.of(context).deviceProfile.isTelevision;
        final showInitialSkeleton =
            loadState == LoadState.loading && items.isEmpty;
        final scrollContent = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isTelevision
                  ? LumaTvLayout.contentMaxWidth
                  : LumaLayout.contentMaxWidth,
            ),
            child: CustomScrollView(
              key: PageStorageKey(
                'library-scroll-${widget.type.name}-${widget.fixedLibraryKind ?? 'all'}',
              ),
              controller: _scroll,
              // 首入场只构建可视区，动效结束后再预构建约半屏内容。
              cacheExtent: _entrySettled ? LumaLayout.scrollCacheExtent : 0,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (controller.isRefreshing)
                  const SliverToBoxAdapter(
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (controller.hasExtraFilters && !isTelevision)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      LumaLayout.pagePaddingH,
                      LumaSpacing.xs,
                      LumaLayout.pagePaddingH,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ActiveFilterBar(controller: controller),
                      ),
                    ),
                  ),
                if (showInitialSkeleton && (isVideo || isTelevision))
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
                else if (showInitialSkeleton)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      LumaSpacing.sm,
                      LumaSpacing.xs,
                      LumaSpacing.sm,
                      LumaSpacing.xl,
                    ),
                    sliver: SliverToBoxAdapter(child: PhotoMasonrySkeleton()),
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
                      // TV：规则网格 + 逐项焦点；触控端保持既有网格。
                      sliver: isTelevision
                          ? TvMediaSliverGrid(
                              items: items,
                              onTap: widget.onOpenMedia,
                              reveal: _tvRevealSafe,
                            )
                          : ResponsiveMediaSliverGrid(
                              items: items,
                              heroTagPrefix: 'videos',
                              onTap: widget.onOpenMedia,
                              onFavorite: (item) => context
                                  .toggleFavoriteWithFeedback(media, item),
                            ),
                    )
                  else if (isTelevision)
                    // TV 图片：规则网格 + 统一画框 contain，保证上下导航可预测；
                    // 不使用瀑布流，视频沿用默认封面填充。
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        LumaLayout.pagePaddingH,
                        LumaSpacing.sm,
                        LumaLayout.pagePaddingH,
                        LumaSpacing.xs,
                      ),
                      sliver: TvMediaSliverGrid(
                        items: items,
                        onTap: _openGallery,
                        artworkFit: BoxFit.contain,
                        reveal: _tvRevealSafe,
                      ),
                    )
                  else
                    SliverLayoutBuilder(
                      builder: (context, constraints) => SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          LumaLayout.pageHorizontalPadding(
                            constraints.crossAxisExtent,
                          ),
                          LumaSpacing.xs,
                          LumaLayout.pageHorizontalPadding(
                            constraints.crossAxisExtent,
                          ),
                          LumaSpacing.xs,
                        ),
                        sliver: MasonryMediaSliver(
                          items: items,
                          spacing: LumaSpacing.xxs,
                          onTap: _openGallery,
                          onLongPress: widget.onLongPressMedia,
                          onFavorite: (item) =>
                              context.toggleFavoriteWithFeedback(media, item),
                        ),
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
        );
        // 触控分支保留下拉刷新；TV 用外层集合承担方向移动与离屏滚动交接。
        final body = isTelevision
            ? scrollContent
            : RefreshIndicator(
                onRefresh: controller.refresh,
                child: scrollContent,
              );
        final scrollHost = isTelevision
            ? LayoutBuilder(
                builder: (context, constraints) => TvFocusCollection(
                  itemIds: _tvIds,
                  axis: Axis.vertical,
                  columns: const TvMediaGridGeometry().columnsFor(
                    constraints.maxWidth.clamp(
                          0,
                          LumaTvLayout.contentMaxWidth,
                        ) -
                        2 * LumaLayout.pagePaddingH,
                  ),
                  revealIndex: _tvRevealSafe.revealIndex,
                  child: body,
                ),
              )
            : body;
        if (isTelevision) {
          final tvPage = Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TvLibraryHeader(
                  title: widget.title ?? (isVideo ? '影音库' : '图片库'),
                  isVideo: isVideo,
                  showBack: !widget.inShell && !widget.embedded,
                  hasExtraFilters: controller.hasExtraFilters,
                  favoritesOnly: controller.favoritesOnly,
                  sort: controller.sort,
                  onSearch: widget.embedded ? null : widget.onOpenSearch,
                  onUpload: isVideo || widget.onUploadImages == null
                      ? null
                      : _openUpload,
                  onRefresh: controller.refresh,
                  onFilters: _openFilters,
                  onFavorites: (selected) => controller.applyFilters(
                    LibraryFilters(favoritesOnly: selected),
                  ),
                  onSort: controller.setSort,
                  onClear: controller.clearFilters,
                ),
                Expanded(child: scrollHost),
              ],
            ),
          );
          return widget.inShell || widget.embedded
              ? tvPage
              : TvKeyBindings(child: TvContentFrame(child: tvPage));
        }
        if (widget.embedded) {
          return Column(
            children: [
              SizedBox(
                height: LumaLayout.minTapTarget,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _actions(),
                ),
              ),
              Expanded(child: scrollHost),
            ],
          );
        }
        final scaffold = Scaffold(
          appBar: AppBar(
            title: ScrollToTopAppBarTitle(
              title: widget.title ?? (isVideo ? '影音库' : '图片库'),
              controller: _scroll,
            ),
            actions: _actions(),
          ),
          body: scrollHost,
        );
        return scaffold;
      },
    );
  }

  List<Widget> _actions() => [
    if (widget.type == MediaType.image && widget.onUploadImages != null)
      IconButton(
        tooltip: '上传图片',
        style: IconButton.styleFrom(
          minimumSize: const Size.square(LumaLayout.minTapTarget),
          visualDensity: VisualDensity.standard,
        ),
        onPressed: _openUpload,
        icon: const Icon(Icons.upload_rounded),
      ),
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
    LibrarySortButton(
      value: _controller?.sort ?? MediaSort.newest,
      onChanged: (sort) => _controller?.setSort(sort),
      showDuration: widget.type == MediaType.video,
    ),
  ];

  /// 上传页关闭后只刷新当前查询，已加载图片在刷新失败时仍然保留。
  Future<void> _openUpload() async {
    final upload = widget.onUploadImages;
    if (upload == null || _uploadPageOpen) return;
    _uploadPageOpen = true;
    try {
      final uploaded = await upload();
      if (mounted && uploaded) await _controller?.refresh();
    } finally {
      _uploadPageOpen = false;
    }
  }

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

  Future<void> _waitForEntrySettle() async {
    await Future.wait<void>([
      waitForRouteTransition(context),
      waitForShellEntrySettle(context),
    ]);
  }

  /// 导航动效结束后恢复屏外缓存，避免首入场同时解码不可见缩略图。
  Future<void> _restoreScrollCacheAfter(Future<void> gate) async {
    await gate;
    if (!mounted || _entrySettled) return;
    setState(() => _entrySettled = true);
  }
}
