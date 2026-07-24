import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../data/models/media_types.dart';
import '../../shared/media/media_artwork.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import '../../shared/states/skeleton.dart';
import 'details_controller.dart';
import 'widgets/detail_information.dart';

class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({
    super.key,
    required this.mediaId,
    this.heroTag,
    this.initialLoadDelay = Duration.zero,
  });

  final String mediaId;

  /// 与来源卡片封面一致的 Hero tag，为空则不启用过渡动画。
  final String? heroTag;

  /// Defers detail data work until a lightweight route transition finishes.
  final Duration initialLoadDelay;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  DetailsController? _controller;
  final _scroll = ScrollController();
  bool _heroTransitionSettled = false;

  @override
  void initState() {
    super.initState();
    if (widget.heroTag == null) {
      _heroTransitionSettled = true;
      return;
    }
    _settleHeroTransition();
  }

  /// Keeps the Hero destination on the card thumbnail until the route flight ends.
  Future<void> _settleHeroTransition() async {
    await Future<void>.delayed(LumaMotion.slow);
    if (mounted) setState(() => _heroTransitionSettled = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= DetailsController(
      mediaId: widget.mediaId,
      media: AppScope.of(context).media,
      initialLoadDelay: widget.initialLoadDelay,
    );
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
        // Video details keep the card thumbnail variant. It is large enough for
        // this surface and avoids replacing the Hero's decoded frame mid-route.
        final useCardThumbnail =
            item.type == MediaType.video || !_heroTransitionSettled;
        final cover = AspectRatio(
          aspectRatio: item.isPortrait ? 3 / 4 : 16 / 10,
          child: MediaArtwork(
            item: item,
            borderRadius: coverRadius,
            useCardThumbnail: useCardThumbnail,
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
                          padding: const EdgeInsets.only(bottom: LumaSpacing.sm),
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
                            const SizedBox(width: LumaSpacing.xl + LumaSpacing.xxs),
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
