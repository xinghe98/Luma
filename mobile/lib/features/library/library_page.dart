import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import '../../shared/media/image_delete_dialog.dart';
import '../shell/shell_entry_gate.dart';
import 'dialogs/library_filter_sheet.dart';
import 'library_controller.dart';
import 'widgets/tv_library_header.dart';
import 'widgets/library_selection_bar.dart';
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

  /// 图片批量选择状态；仅图片库维护。
  final Set<String> _selectedIds = {};
  bool _selectMode = false;

  /// 删除批次状态：确认后即置 [_deleting]，防重入与误触；
  /// [_deleteStop] 表示用户要求当前项完成后停止剩余批次。
  bool _deleting = false;
  bool _confirmingDelete = false;
  bool _deleteStop = false;
  int _deleteTotal = 0;
  int _deleteDone = 0;
  String? _selectionError;

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
    assert(items.any((entry) => entry.id == item.id), '点击图片必须来自当前可见列表');
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
      // 已确认删除的图片不再借后续分页回到预览会话。
      isRemoved: AppScope.of(context).media.isDeleted,
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
                        onTap: _onMediaTap,
                        artworkFit: BoxFit.contain,
                        reveal: _tvRevealSafe,
                        selectionMode: _selectMode,
                        selectedIds: _selectedIds,
                        onLongPress: _selectMode
                            ? null
                            : widget.onLongPressMedia,
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
                          onTap: _onMediaTap,
                          onLongPress: _selectMode
                              ? null
                              : widget.onLongPressMedia,
                          onFavorite: (item) =>
                              context.toggleFavoriteWithFeedback(media, item),
                          selectionMode: _selectMode,
                          selectedIds: _selectedIds,
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
                  selectionMode: _selectMode,
                  selectedCount: _selectedIds.length,
                  onToggleSelect: isVideo ? null : _toggleSelectionMode,
                  onDeleteSelected: isVideo ? null : _deleteSelected,
                  onSelectAll: isVideo ? null : _selectAllLoaded,
                  onCancelSelection: isVideo ? null : _cancelOrStopSelection,
                  deleting: _deleting,
                  deleteTotal: _deleteTotal,
                  deleteDone: _deleteDone,
                ),
                Expanded(child: scrollHost),
              ],
            ),
          );
          return widget.inShell || widget.embedded
              ? tvPage
              : _SelectionScope(
                  active: _selectMode,
                  busy: _deleting,
                  onCancel: _cancelOrStopSelection,
                  child: TvKeyBindings(child: TvContentFrame(child: tvPage)),
                );
        }
        if (widget.embedded) {
          return Column(
            children: [
              SizedBox(
                height: LumaLayout.minTapTarget,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _actions(context),
                ),
              ),
              Expanded(child: scrollHost),
            ],
          );
        }
        return _SelectionScope(
          active: _selectMode,
          busy: _deleting,
          onCancel: _cancelOrStopSelection,
          child: Scaffold(
            appBar: AppBar(
              title: ScrollToTopAppBarTitle(
                title: widget.title ?? (isVideo ? '影音库' : '图片库'),
                controller: _scroll,
              ),
              actions: _actions(context),
            ),
            body: scrollHost,
            bottomNavigationBar: _selectMode ? _selectionBar() : null,
          ),
        );
      },
    );
  }

  /// 进入或退出图片批量选择；删除进行中锁定退出，只能先停止批次。
  void _toggleSelectionMode() {
    if (_deleting) return;
    setState(() {
      _selectMode = !_selectMode;
      _selectedIds.clear();
      _selectionError = null;
    });
  }

  /// 普通态退出选择；删除中改为请求停止剩余批次（当前请求完成即止）。
  void _cancelOrStopSelection() {
    if (_deleting) {
      _requestDeleteStop();
      return;
    }
    _toggleSelectionMode();
  }

  /// 请求批次在下一个 await 边界停止；不中断已发出的删除请求。
  void _requestDeleteStop() {
    if (!_deleting || _deleteStop) return;
    setState(() => _deleteStop = true);
  }

  /// 切换单个已加载项的选中态；不在选择态或删除中时忽略。
  void _toggleSelectItem(MediaItem item) {
    if (!_selectMode || _deleting || widget.type != MediaType.image) return;
    setState(() {
      if (!_selectedIds.remove(item.id)) _selectedIds.add(item.id);
      _selectionError = null;
    });
  }

  /// 仅全选当前已加载的项目，避免暗示覆盖远端未加载分页。
  void _selectAllLoaded() {
    final controller = _controller;
    if (!_selectMode || _deleting || controller == null) return;
    setState(() {
      _selectedIds.addAll(controller.visibleItems().map((item) => item.id));
      _selectionError = null;
    });
  }

  /// 删除前确认并逐条请求后端；每项完成后更新进度与选择集合。
  /// 会话切换（换服/重连）立即停止并清空选择，避免把旧勾选误删到新服务器。
  Future<void> _deleteSelected() async {
    final media = AppScope.of(context).media;
    // 确认等待期也要防重入：重复点击删除不会再起第二个确认框。
    if (_deleting || _confirmingDelete || _selectedIds.isEmpty) return;
    final generation = media.sessionGeneration;
    _confirmingDelete = true;
    bool confirmed;
    try {
      confirmed = await confirmImageDeletion(
        context,
        count: _selectedIds.length,
      );
    } finally {
      _confirmingDelete = false;
    }
    if (!mounted ||
        !confirmed ||
        _deleting ||
        generation != media.sessionGeneration) {
      return;
    }
    final ids = _selectedIds.toList(growable: false);
    setState(() {
      _deleting = true;
      _deleteStop = false;
      _deleteTotal = ids.length;
      _deleteDone = 0;
      _selectionError = null;
    });
    var failures = 0;
    var stopped = false;
    var sessionChanged = false;
    for (final id in ids) {
      if (!mounted || _deleteStop || generation != media.sessionGeneration) {
        stopped = _deleteStop && generation == media.sessionGeneration;
        sessionChanged = generation != media.sessionGeneration;
        break;
      }
      try {
        await media.deleteImage(id);
        if (!mounted) return;
        setState(() {
          _selectedIds.remove(id);
          _deleteDone++;
        });
      } on Object {
        if (!mounted) return;
        setState(() {
          failures++;
          _deleteDone++;
        });
      }
    }
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _deleteStop = false;
      _deleteTotal = 0;
      _deleteDone = 0;
      if (sessionChanged) {
        // 新会话下旧勾选可能指向不同媒体，必须整体作废；
        // 保留选择态仅作提示承载，由用户显式退出。
        _selectedIds.clear();
        _selectionError = '连接已更改，已清空选择';
      } else {
        _selectionError = failures == 0
            ? (stopped ? '已停止剩余删除' : null)
            : '有 $failures 项删除失败，仍在选择列表中，可重试';
        if (_selectedIds.isEmpty && !stopped) _selectMode = false;
      }
    });
  }

  /// 选择态下点击卡片只切换选中；否则进入预览。
  void _onMediaTap(MediaItem item, {String? heroTag}) {
    if (_selectMode) {
      _toggleSelectItem(item);
      return;
    }
    _openGallery(item, heroTag: heroTag);
  }

  /// 选择态操作栏：呈现与回调在 [LibrarySelectionBar]，状态由页面持有。
  Widget _selectionBar() => LibrarySelectionBar(
    selectedCount: _selectedIds.length,
    deleting: _deleting,
    deleteTotal: _deleteTotal,
    deleteDone: _deleteDone,
    onSelectAll: _selectAllLoaded,
    onDelete: _deleteSelected,
    onCancelOrStop: _cancelOrStopSelection,
    error: _selectionError,
  );

  /// 窄屏时把次要操作收进溢出菜单：上传/选择/搜索保持独立 48dp 可达，
  /// 收藏与排序合并为 PopupMenuButton，避免 320px + 大字号下溢出 AppBar。
  List<Widget> _actions(BuildContext context) {
    final isImage = widget.type == MediaType.image;
    // 紧凑分支在更宽的窗口才展开全部按钮；阈值按已上传图库的最大操作数设定。
    final compact =
        MediaQuery.sizeOf(context).width < LumaLayout.actionWidthBreakpoint;
    final primary = <Widget>[
      if (isImage && widget.onUploadImages != null)
        IconButton(
          tooltip: '上传图片',
          style: IconButton.styleFrom(
            minimumSize: const Size.square(LumaLayout.minTapTarget),
            visualDensity: VisualDensity.standard,
          ),
          onPressed: _openUpload,
          icon: const Icon(Icons.upload_rounded),
        ),
      if (isImage)
        IconButton(
          tooltip: _selectMode ? '退出选择' : '选择图片',
          style: IconButton.styleFrom(
            minimumSize: const Size.square(LumaLayout.minTapTarget),
            visualDensity: VisualDensity.standard,
          ),
          // 删除中退出按钮解释为停止剩余批次，避免误以为已取消仍在删除。
          onPressed: _selectMode && _deleting
              ? _requestDeleteStop
              : _toggleSelectionMode,
          icon: Icon(
            _selectMode ? Icons.close_rounded : Icons.checklist_rounded,
          ),
        ),
      if (!widget.embedded)
        IconButton(
          tooltip: '搜索',
          onPressed: widget.onOpenSearch,
          icon: const Icon(Icons.search_rounded),
        ),
    ];
    final secondary = <Widget>[
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
            LibraryFilters(
              favoritesOnly: !(_controller?.favoritesOnly ?? false),
            ),
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
    if (!compact) return [...primary, ...secondary];
    // 紧凑分支：收藏与排序合入一个溢出菜单，菜单项仍保留完整 48dp 行高。
    final favoritesOnly = _controller?.favoritesOnly ?? false;
    return [
      ...primary,
      PopupMenuButton<String>(
        tooltip: '更多操作',
        icon: Badge(
          isLabelVisible: favoritesOnly,
          child: const Icon(Icons.more_vert_rounded),
        ),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'favorite',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                favoritesOnly
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              title: Text(favoritesOnly ? '显示全部图片' : '仅显示收藏'),
            ),
          ),
          PopupMenuItem(
            enabled: false,
            child: LibrarySortButton(
              value: _controller?.sort ?? MediaSort.newest,
              onChanged: (sort) {
                Navigator.of(context).pop();
                _controller?.setSort(sort);
              },
              showDuration: widget.type == MediaType.video,
            ),
          ),
        ],
        onSelected: (value) {
          if (value == 'favorite') {
            _controller?.applyFilters(
              LibraryFilters(favoritesOnly: !favoritesOnly),
            );
          }
        },
      ),
    ];
  }

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

/// 选择态下的返回/Escape 作用域：路由 PopScope 拦截系统返回并先退出选择，
/// FocusScope 在键盘上把 Back/Escape 映射为同一取消动作，避免双重处理。
/// 删除进行中 [busy] 为 true：返回只请求停止剩余批次，既不清空勾选也不出栈。
class _SelectionScope extends StatelessWidget {
  const _SelectionScope({
    required this.active,
    required this.busy,
    required this.onCancel,
    required this.child,
  });

  /// 是否处于选择态；false 时按键与返回都透传给下层。
  final bool active;

  /// 是否正在执行批量删除；true 时 Back/Escape 只请求停止剩余批次。
  final bool busy;

  /// 非删除态的退出选择，或删除态的停止剩余批次；由调用方按 [busy] 判定。
  final VoidCallback onCancel;

  final Widget child;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!active) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.escape && key != LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) onCancel();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !active,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onCancel();
    },
    child: FocusScope(onKeyEvent: _handleKey, child: child),
  );
}
