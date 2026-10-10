import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../../app/app_scope.dart';
import '../../app/controllers/media_controller.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../shell/app_destination.dart';
import '../../shared/media/media_actions.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import 'home_controller.dart';
import 'widgets/continue_spotlight.dart';
import 'widgets/home_header.dart';
import 'widgets/horizontal_media_section.dart';
import 'widgets/library_status_banner.dart';
import 'widgets/recent_media_section.dart';
import 'widgets/tv_home_feature.dart';

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
  int? _prewarmEpoch;
  bool _prewarmSchedulePending = false;

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
    final isTelevision = AppScope.of(context).deviceProfile.isTelevision;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            // 每次媒体通知都重建状态分支与货架，避免复用过期的整页快照。
            final scrollableView = _buildScrollView(context, isTelevision);
            return isTelevision
                ? scrollableView
                : RefreshIndicator(
                    onRefresh: controller.media.refresh,
                    child: scrollableView,
                  );
          },
        ),
      ),
    );
  }

  Widget _buildScrollView(BuildContext context, bool isTelevision) {
    final controller = _controller!;
    if (controller.media.loadState == LoadState.ready &&
        controller.media.items.isNotEmpty) {
      _scheduleBranchPrewarm();
    }
    final continuing = controller.continuing;
    final recent = controller.recent;
    final featured = continuing.firstOrNull ?? recent.firstOrNull;
    return CustomScrollView(
      key: const PageStorageKey('home-scroll'),
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: isTelevision
              ? TvHomeFeature(
                  item: featured,
                  onOpen: () {
                    if (featured != null) widget.onOpenMedia(featured);
                  },
                  onRefresh: controller.media.refresh,
                )
              : HomeTopBar(
                  onOpenSearch: widget.onOpenSearch,
                  onScrollToTop: _scrollToTop,
                ),
        ),
        const SliverToBoxAdapter(child: LibraryStatusBanner()),
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
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: '媒体库还没有内容',
              message: '等待服务器扫描完成，或前往设置手动开始扫描。',
              icon: Icons.video_library_outlined,
              action: FilledButton.tonal(
                onPressed: () =>
                    context.goToDestination(AppDestination.settings),
                child: const Text('查看扫描状态'),
              ),
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
          // 触控端用大卡聚焦第一项；TV 首页结构不变，继续沿用整排货架。
          if (continuing.isNotEmpty && !isTelevision)
            SliverToBoxAdapter(
              child: ContinueSpotlight(
                item: continuing.first,
                upNext: continuing.skip(1).take(3).toList(growable: false),
                onOpen: widget.onOpenMedia,
              ),
            ),
          if (isTelevision ? continuing.isNotEmpty : continuing.length > 4)
            SliverToBoxAdapter(
              child: HorizontalMediaSection(
                title: '继续观看',
                heroPrefix: 'continue',
                items: isTelevision
                    ? continuing.take(8).toList(growable: false)
                    : continuing.skip(4).toList(growable: false),
                onOpenMedia: widget.onOpenMedia,
                onFavorite: (item) =>
                    context.toggleFavoriteWithFeedback(controller.media, item),
              ),
            ),
          SliverToBoxAdapter(
            child: RecentMediaSection(
              items: recent,
              onOpenMedia: widget.onOpenMedia,
              onFavorite: (item) =>
                  context.toggleFavoriteWithFeedback(controller.media, item),
            ),
          ),
          SliverToBoxAdapter(
            child: HorizontalMediaSection(
              title: '收藏',
              heroPrefix: 'favorites',
              items: controller.favorites,
              onOpenMedia: widget.onOpenMedia,
              onFavorite: (item) =>
                  context.toggleFavoriteWithFeedback(controller.media, item),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: LumaSpacing.lg)),
        ],
      ],
    );
  }

  void _scrollToTop() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    _scroll.jumpTo(0);
  }

  /// 首页内容稳定后把媒体分支预热排入空闲队列，同一服务器会话只安排一次。
  void _scheduleBranchPrewarm() {
    if (_prewarmSchedulePending) return;
    final dependencies = AppScope.of(context);
    final epoch = dependencies.apiSession.epoch;
    if (_prewarmEpoch == epoch || dependencies.apiSession.origin.isEmpty) {
      return;
    }
    _prewarmSchedulePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prewarmSchedulePending = false;
      if (!mounted || dependencies.apiSession.epoch != epoch) return;
      _prewarmEpoch = epoch;
      dependencies.mediaBranchPrewarmer.schedule(context);
    });
  }
}
