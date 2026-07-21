import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../shared/media/media_artwork.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import 'details_controller.dart';
import 'widgets/detail_information.dart';

class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({super.key, required this.mediaId, this.heroTag});

  final String mediaId;

  /// 与来源卡片封面一致的 Hero tag，为空则不启用过渡动画。
  final String? heroTag;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  DetailsController? _controller;
  final _scroll = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= DetailsController(
      mediaId: widget.mediaId,
      media: AppScope.of(context).media,
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
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: controller.isLoading
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            controller.detailError ?? '找不到该媒体，可能已被移除或尚未加载。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
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
        final cover = AspectRatio(
          aspectRatio: item.isPortrait ? 3 / 4 : 16 / 10,
          child: MediaArtwork(item: item, borderRadius: LumaRadii.large),
        );
        final artwork = widget.heroTag == null
            ? cover
            : Hero(tag: widget.heroTag!, child: cover);
        return Scaffold(
          appBar: AppBar(
            title: ScrollToTopAppBarTitle(title: '媒体详情', controller: _scroll),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
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
                          padding: const EdgeInsets.only(bottom: 12),
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
                            const SizedBox(width: 36),
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
