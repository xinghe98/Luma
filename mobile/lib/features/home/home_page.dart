import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/controllers/media_controller.dart';
import '../../core/extensions.dart';
import '../../shared/media/media_actions.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import 'home_controller.dart';
import 'widgets/home_header.dart';
import 'widgets/horizontal_media_section.dart';
import 'widgets/recent_media_section.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onOpenMedia,
    required this.onOpenSearch,
  });

  final MediaOpenCallback onOpenMedia;
  final VoidCallback onOpenSearch;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin<HomePage> {
  HomeController? _controller;
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= HomeController(AppScope.of(context).media);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = _controller!;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => RefreshIndicator(
            onRefresh: controller.media.refresh,
            child: CustomScrollView(
              key: const PageStorageKey('home-scroll'),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: HomeHeader(
                    onOpenSearch: widget.onOpenSearch,
                    onScrollToTop: _scrollToTop,
                  ),
                ),
                if (controller.media.loadState == LoadState.loading &&
                    controller.media.items.isEmpty)
                  const SliverToBoxAdapter(child: HomeFeedSkeleton())
                else if (controller.media.loadState == LoadState.error &&
                    controller.media.items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorState(onRetry: controller.media.load),
                  )
                else if (controller.media.items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      title: '媒体库还没有内容',
                      message: '等待服务器扫描完成，或前往设置手动开始扫描。',
                      icon: Icons.video_library_outlined,
                    ),
                  )
                else ...[
                  if (controller.media.loadState == LoadState.error)
                    SliverToBoxAdapter(
                      child: ErrorState(
                        compact: true,
                        title: '首页刷新失败',
                        message: '当前仍显示上次成功加载的内容。',
                        retryLabel: '重试刷新',
                        onRetry: controller.media.refresh,
                      ),
                    ),
                  if (controller.media.loadState == LoadState.loading)
                    const SliverToBoxAdapter(
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  SliverToBoxAdapter(
                    child: HorizontalMediaSection(
                      title: '继续观看',
                      subtitle: '回到上次停下的位置',
                      heroPrefix: 'continue',
                      items: controller.continuing,
                      onOpenMedia: widget.onOpenMedia,
                      onFavorite: (item) => context.toggleFavoriteWithFeedback(
                        controller.media,
                        item,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: RecentMediaSection(
                      items: controller.recent,
                      onOpenMedia: widget.onOpenMedia,
                      onFavorite: (item) => context.toggleFavoriteWithFeedback(
                        controller.media,
                        item,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: HorizontalMediaSection(
                      title: '收藏',
                      subtitle: '留给以后再看的片段',
                      heroPrefix: 'favorites',
                      items: controller.favorites,
                      onOpenMedia: widget.onOpenMedia,
                      onFavorite: (item) => context.toggleFavoriteWithFeedback(
                        controller.media,
                        item,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToTop() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    _scroll.jumpTo(0);
  }
}
