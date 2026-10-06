import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/controllers/media_controller.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../shared/interaction/tv_focus_collection.dart';
import '../../shared/media/media_actions.dart';
import '../../shared/media/tv_media_grid.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import '../shell/widgets/tv_field_gate.dart';
import 'search_controller.dart' as feature;
import 'widgets/recent_searches.dart';
import 'widgets/search_filters.dart';
import 'widgets/search_input.dart';
import 'widgets/search_results.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.onOpenMedia});

  final MediaOpenCallback onOpenMedia;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin<SearchPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();
  FocusNode? _searchFocusField;

  /// TV：输入框节点不参与方向遍历，浏览焦点在 TvTextFieldGate 闸门上，
  /// OK 才进入编辑并弹出 IME；普通端节点保持默认遍历行为。
  FocusNode get _searchFocus => _searchFocusField ??= FocusNode(
    debugLabel: 'search-input',
    skipTraversal: AppScope.of(context).deviceProfile.isTelevision,
  );

  /// TV：提交查询后聚焦首个结果；普通端不使用。
  final _firstResultFocus = FocusNode(debugLabel: 'tv-first-result');
  (String, Object?, String?)? _pendingResultFocus;
  int _submissionGeneration = 0;

  /// TV 网格的滚动基准与稳定 id 表。
  TvGridReveal? _tvReveal;
  List<String>? _tvItemIds;
  bool _loadMoreCheckScheduled = false;

  feature.SearchController? _controller;

  TvGridReveal get _tvRevealSafe =>
      _tvReveal ??= TvGridReveal(controller: _scroll);

  void _invalidateTvIds() => _tvItemIds = null;

  List<String> get _tvIds {
    var ids = _tvItemIds;
    final items = _controller?.results ?? const [];
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
    // 订阅路由可见性；离开即撤销提交意图，返回时不恢复旧焦点交接。
    if (ModalRoute.isCurrentOf(context) == false) {
      _pendingResultFocus = null;
      _submissionGeneration++;
    }
    if (_controller != null) return;
    final controller = feature.SearchController(AppScope.of(context).media);
    _controller = controller;
    controller.addListener(_onControllerChanged);
    controller.addListener(_invalidateTvIds);
  }

  @override
  void dispose() {
    _text.dispose();
    _searchFocus.dispose();
    _firstResultFocus.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _controller
      ?..removeListener(_onControllerChanged)
      ..removeListener(_invalidateTvIds)
      ..dispose();
    super.dispose();
  }

  /// 提交意图绑定查询条件；已完成的查询立即移交，后续输入取消旧意图。
  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (AppScope.of(context).deviceProfile.isTelevision) {
      _scheduleLoadMoreCheck();
    }
    final pending = _pendingResultFocus;
    if (pending == null) return;
    final criteria = (controller.query, controller.type, controller.tagId);
    if (criteria != pending || controller.loadState == LoadState.error) {
      _pendingResultFocus = null;
      _submissionGeneration++;
      return;
    }
    if (controller.loadState != LoadState.ready) return;
    _pendingResultFocus = null;
    final generation = _submissionGeneration;
    if (controller.results.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_revealSubmittedResult(generation, pending));
    });
  }

  /// 先揭示结果再交接焦点；不依赖平台焦点高亮模式触发隐式滚动。
  Future<void> _revealSubmittedResult(
    int generation,
    (String, Object?, String?) criteria,
  ) async {
    if (!_isCurrentSubmission(generation, criteria)) return;
    if (_firstResultFocus.context == null) {
      final resultsContext = _resultsKey.currentContext;
      if (resultsContext == null) return;
      await Scrollable.ensureVisible(resultsContext);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!_isCurrentSubmission(generation, criteria)) return;
    final target = _firstResultFocus.context;
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(target);
    if (_isCurrentSubmission(generation, criteria)) {
      _firstResultFocus.requestFocus();
    }
  }

  bool _isCurrentSubmission(
    int generation,
    (String, Object?, String?) criteria,
  ) =>
      mounted &&
      generation == _submissionGeneration &&
      _controller!.query == criteria.$1 &&
      _controller!.type == criteria.$2 &&
      _controller!.tagId == criteria.$3 &&
      ModalRoute.of(context)?.isCurrent != false;

  /// TV 首屏未填满时在帧末补一次加载检查；守卫与滚动加载一致，
  /// 不重复请求，也不自动重试已出错的分页。
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
    if (controller == null ||
        !controller.hasMore ||
        controller.isLoadingMore ||
        controller.hasLoadMoreError) {
      return;
    }
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 720) {
      controller.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final media = AppScope.of(context).media;
    final controller = _controller!;
    final isTelevision = AppScope.of(context).deviceProfile.isTelevision;
    // 只听搜索控制器；标签变更由 controller 选择性转发。
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final results = SearchResults(
          items: controller.results,
          hasCriteria: controller.hasCriteria,
          searchState: controller.loadState,
          onOpenMedia: widget.onOpenMedia,
          onFavorite: (item) => context.toggleFavoriteWithFeedback(media, item),
          onClear: _clearAll,
          onSearchRetry: controller.retry,
          hasMore: controller.hasMore,
          isLoadingMore: controller.isLoadingMore,
          hasLoadMoreError: controller.hasLoadMoreError,
          onLoadMoreRetry: controller.loadMore,
          television: isTelevision,
          reveal: isTelevision ? _tvRevealSafe : null,
          firstResultFocusNode: isTelevision ? _firstResultFocus : null,
        );
        final scrollBody = CustomScrollView(
          key: const PageStorageKey('search-scroll'),
          controller: _scroll,
          cacheExtent: LumaLayout.scrollCacheExtent,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                LumaLayout.pagePaddingH,
                LumaSpacing.xs,
                LumaLayout.pagePaddingH,
                0,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  if (isTelevision) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '搜索',
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                          ),
                          RecentSearches(
                            terms: controller.recent,
                            onSelect: _selectRecent,
                            onClear: controller.clearRecent,
                            television: true,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TvTextFieldGate(
                            fieldFocusNode: _searchFocus,
                            builder: (context, gateFocused) => SearchInput(
                              textController: _text,
                              focusNode: _searchFocus,
                              autofocus: false,
                              television: gateFocused,
                              remoteLayout: true,
                              onChanged: controller.setQuery,
                              onSubmitted: _onSubmitted,
                              onClear: _clearQuery,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          key: const ValueKey('tv-submit-search'),
                          onPressed: () => _onSubmitted(_text.text),
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('搜索'),
                        ),
                        if (controller.hasCriteria) ...[
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _clearAll,
                            child: const Text('清除'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                  ] else
                    SearchInput(
                      textController: _text,
                      focusNode: _searchFocus,
                      autofocus: true,
                      onChanged: controller.setQuery,
                      onSubmitted: controller.remember,
                      onClear: _clearQuery,
                    ),
                  if (!isTelevision)
                    RecentSearches(
                      terms: controller.recent,
                      onSelect: _selectRecent,
                      onClear: controller.clearRecent,
                    ),
                  SearchFilters(
                    type: controller.type,
                    tagId: controller.tagId,
                    tags: controller.tags,
                    onType: controller.setType,
                    onTag: controller.toggleTag,
                    television: isTelevision,
                  ),
                  if (isTelevision) const SizedBox(height: 24),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                LumaLayout.pagePaddingH,
                0,
                LumaLayout.pagePaddingH,
                LumaSpacing.xl,
              ),
              sliver: SliverMainAxisGroup(
                key: _resultsKey,
                slivers: results.buildSlivers(),
              ),
            ),
          ],
        );
        final content = isTelevision
            // TV 外层集合承担结果网格的方向移动与离屏滚动交接。
            ? LayoutBuilder(
                builder: (context, constraints) => TvFocusCollection(
                  itemIds: _tvIds,
                  axis: Axis.vertical,
                  columns: const TvMediaGridGeometry().columnsFor(
                    constraints.maxWidth - 2 * LumaLayout.pagePaddingH,
                  ),
                  revealIndex: _tvRevealSafe.revealIndex,
                  child: scrollBody,
                ),
              )
            : scrollBody;
        return Scaffold(
          appBar: isTelevision
              ? null
              : AppBar(
                  title: ScrollToTopAppBarTitle(
                    title: '搜索',
                    controller: _scroll,
                  ),
                ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isTelevision
                    ? LumaTvLayout.contentMaxWidth
                    : LumaLayout.contentMaxWidth,
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }

  /// 显式提交（IME Done/搜索键）才记录查询并把焦点移交首个结果；
  /// 防抖响应不改变焦点。
  void _onSubmitted(String term) {
    final controller = _controller!;
    if (AppScope.of(context).deviceProfile.isTelevision) {
      _submissionGeneration++;
      _pendingResultFocus = (
        controller.query,
        controller.type,
        controller.tagId,
      );
    }
    controller.remember(term);
    _onControllerChanged();
  }

  void _selectRecent(String term) {
    _text.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    _pendingResultFocus = null;
    _submissionGeneration++;
    _controller!.setQuery(term);
    _onSubmitted(term);
  }

  void _clearQuery() {
    _text.clear();
    _pendingResultFocus = null;
    _submissionGeneration++;
    _controller!.setQuery('');
  }

  void _clearAll() {
    _text.clear();
    _pendingResultFocus = null;
    _submissionGeneration++;
    _controller!.clearCriteria();
  }

  void _onScroll() {
    final controller = _controller;
    if (controller == null ||
        !controller.hasMore ||
        controller.isLoadingMore ||
        controller.hasLoadMoreError ||
        !_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 720) {
      controller.loadMore();
    }
  }
}
