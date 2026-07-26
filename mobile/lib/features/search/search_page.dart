import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../shared/media/media_actions.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
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
  feature.SearchController? _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final media = AppScope.of(context).media;
    final controller = _controller ??= feature.SearchController(media);
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
        );
        return Scaffold(
          appBar: AppBar(
            title: ScrollToTopAppBarTitle(title: '搜索', controller: _scroll),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LumaLayout.contentMaxWidth,
              ),
              child: CustomScrollView(
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
                        SearchInput(
                          textController: _text,
                          onChanged: controller.setQuery,
                          onSubmitted: controller.remember,
                          onClear: _clearQuery,
                        ),
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
                        ),
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
                      slivers: results.buildSlivers(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectRecent(String term) {
    _text.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    _controller!.setQuery(term);
  }

  void _clearQuery() {
    _text.clear();
    _controller!.setQuery('');
  }

  void _clearAll() {
    _text.clear();
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
