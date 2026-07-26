import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/route_transition.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import '../../shared/media/media_artwork.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import '../../shared/states/skeleton.dart';
import 'details_controller.dart';
import 'widgets/detail_information.dart';

class MediaDetailPage extends StatefulWidget {
  /// 显示媒体详情，优先使用路由携带条目并在真实入场动画后刷新。
  const MediaDetailPage({
    super.key,
    required this.mediaId,
    this.initialItem,
    this.heroTag,
  });

  final String mediaId;
  final MediaItem? initialItem;

  /// 与来源卡片封面一致的 Hero tag，为空则不启用过渡动画。
  final String? heroTag;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  DetailsController? _controller;
  final _scroll = ScrollController();
  bool _loadScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final media = AppScope.of(context).media;
    final initialItem = widget.initialItem;
    if (initialItem != null && initialItem.id == widget.mediaId) {
      media.remember(initialItem, notify: false);
    }
    _controller = DetailsController(
      mediaId: widget.mediaId,
      media: media,
      loadImmediately: false,
      showCachedBeforeInitialLoad: initialItem != null,
    );
    if (!_loadScheduled) {
      _loadScheduled = true;
      _refreshAfterTransition();
    }
  }

  /// 路由与 Hero 完全结束后再刷新，避免共享封面飞行期间替换图片来源。
  Future<void> _refreshAfterTransition() async {
    await waitForRouteTransition(context);
    if (!mounted) return;
    await _controller?.reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller!,
      builder: (context, _) {
        final controller = _controller!;
        final item = controller.item;
        if (item == null) {
          return Scaffold(
            appBar: AppBar(
              title: ScrollToTopAppBarTitle(title: '媒体详情', controller: _scroll),
            ),
            body: controller.isLoading
                ? const DetailPageSkeleton()
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(LumaSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            controller.detailError ?? '找不到该媒体，可能已被移除或尚未加载。',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: LumaSpacing.md),
                          FilledButton(
                            onPressed: controller.reload,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
          );
        }
        final coverRadius = context.luma.coverRadius;
        final cover = AspectRatio(
          aspectRatio: item.isPortrait ? 3 / 4 : 16 / 10,
          child: MediaArtwork(
            item: item,
            borderRadius: coverRadius,
            useCardThumbnail: item.type == MediaType.video,
            cacheWidth: widget.heroTag == null
                ? null
                : MediaArtwork.heroThumbnailCacheWidth,
          ),
        );
        final artwork = widget.heroTag == null
            ? cover
            : Hero(
                tag: widget.heroTag!,
                flightShuttleBuilder: MediaArtwork.preserveSourceHeroFlight,
                child: cover,
              );
        return Scaffold(
          appBar: AppBar(
            title: ScrollToTopAppBarTitle(title: '媒体详情', controller: _scroll),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              controller: _scroll,
              padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: LumaLayout.detailMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (controller.detailError != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: LumaSpacing.sm,
                          ),
                          child: MaterialBanner(
                            content: Text(controller.detailError!),
                            actions: [
                              TextButton(
                                onPressed: controller.reload,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      if (constraints.maxWidth >=
                          LumaLayout.detailTwoColumnBreakpoint)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: artwork),
                            const SizedBox(
                              width: LumaSpacing.xl + LumaSpacing.xxs,
                            ),
                            Expanded(
                              flex: 6,
                              child: DetailInformation(controller: controller),
                            ),
                          ],
                        )
                      else ...[
                        artwork,
                        const SizedBox(height: LumaSpacing.xl),
                        DetailInformation(controller: controller),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
