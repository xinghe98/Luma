part of '../catalog_page.dart';

class _CatalogShelfSection extends StatelessWidget {
  const _CatalogShelfSection({
    required this.title,
    required this.controller,
    required this.onOpenCatalog,
    required this.onOpenAll,
    this.entryFocusId,
    this.onEntryFocused,
  });

  final String title;
  final CatalogController controller;
  final CatalogOpenCallback onOpenCatalog;
  final ValueChanged<List<CatalogItem>> onOpenAll;
  final String? entryFocusId;
  final VoidCallback? onEntryFocused;

  @override
  Widget build(BuildContext context) {
    void openAll() =>
        onOpenAll(controller.items.take(12).toList(growable: false));
    if (controller.items.isEmpty &&
        controller.state == CatalogLoadState.error) {
      return _CatalogSectionIssue(
        title: title,
        onRetry: controller.load,
        onOpenAll: openAll,
      );
    }
    if (controller.items.isEmpty &&
        controller.state != CatalogLoadState.ready) {
      return _CatalogShelfPlaceholder(title: title, onOpenAll: openAll);
    }
    if (controller.items.isEmpty) {
      return _CatalogSectionEmpty(title: title, onOpenAll: openAll);
    }
    return _CatalogShelf(
      title: title,
      items: controller.items,
      onOpenCatalog: onOpenCatalog,
      onOpenAll: openAll,
      loading: controller.state == CatalogLoadState.loading,
      hasError: controller.state == CatalogLoadState.error,
      onRetry: controller.load,
      entryFocusId: entryFocusId,
      onEntryFocused: onEntryFocused,
    );
  }
}

class _CatalogShelfPlaceholder extends StatelessWidget {
  const _CatalogShelfPlaceholder({
    required this.title,
    required this.onOpenAll,
  });

  final String title;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    if (AppScope.of(context).deviceProfile.isTelevision) {
      const cardWidth = LumaTvLayout.posterMinWidth + 24;
      return Padding(
        padding: const EdgeInsets.only(top: LumaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeading(title: title, onOpenAll: onOpenAll),
            const SizedBox(height: LumaSpacing.md),
            SizedBox(
              height:
                  cardWidth * 1.5 +
                  MediaCard.textDetailsHeight(context, titleLines: 1),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: LumaLayout.pagePaddingH,
                ),
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 8,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: LumaTvLayout.cardSpacing),
                itemBuilder: (_, _) => const SizedBox(
                  width: cardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                        height: cardWidth * 1.5,
                        radius: LumaRadii.large,
                      ),
                      SizedBox(height: 12),
                      SkeletonBox(height: 18, width: 136),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: LumaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(title: title, onOpenAll: onOpenAll),
          const SizedBox(height: LumaSpacing.md),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: LumaLayout.pagePaddingH),
            child: SizedBox(
              height: 262,
              child: Row(
                children: [
                  Expanded(
                    child: SkeletonBox(
                      height: double.infinity,
                      radius: LumaRadii.large,
                    ),
                  ),
                  SizedBox(width: LumaSpacing.md),
                  Expanded(
                    child: SkeletonBox(
                      height: double.infinity,
                      radius: LumaRadii.large,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogSectionIssue extends StatelessWidget {
  const _CatalogSectionIssue({
    required this.title,
    required this.onRetry,
    required this.onOpenAll,
  });

  final String title;
  final VoidCallback onRetry;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        SizedBox(
          height: 262,
          child: Center(
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                AppScope.of(context).deviceProfile.isTelevision
                    ? '加载失败，重试'
                    : '加载失败，轻触重试',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CatalogSectionEmpty extends StatelessWidget {
  const _CatalogSectionEmpty({required this.title, required this.onOpenAll});

  final String title;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        SizedBox(
          height: 108,
          child: Center(
            child: Text(
              '暂时没有$title',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CatalogShelf extends StatelessWidget {
  const _CatalogShelf({
    required this.title,
    required this.items,
    required this.onOpenCatalog,
    required this.onOpenAll,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    this.entryFocusId,
    this.onEntryFocused,
  });

  final String title;
  final List<CatalogItem> items;
  final CatalogOpenCallback onOpenCatalog;
  final VoidCallback onOpenAll;
  final bool loading;
  final bool hasError;
  final VoidCallback onRetry;
  final String? entryFocusId;
  final VoidCallback? onEntryFocused;

  @override
  Widget build(BuildContext context) {
    final isTelevision = AppScope.of(context).deviceProfile.isTelevision;
    return Padding(
      padding: EdgeInsets.only(
        top: isTelevision ? LumaSpacing.sm : LumaSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeading(title: title, onOpenAll: onOpenAll),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: LumaSpacing.xs),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (hasError)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LumaLayout.pagePaddingH,
                ),
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新失败，当前保留上次内容'),
                ),
              ),
            ),
          const SizedBox(height: LumaSpacing.md),
          // TV：大海报货架与逐项焦点；触控端保持既有小卡与箭头-free 横滑。
          if (isTelevision)
            _TvCatalogShelf(
              items: items,
              onOpenCatalog: onOpenCatalog,
              entryFocusId: entryFocusId,
              onEntryFocused: onEntryFocused,
            )
          else
            SizedBox(
              height: 262,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: LumaLayout.pagePaddingH,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: items.length.clamp(0, 12),
                separatorBuilder: (_, _) =>
                    const SizedBox(width: LumaSpacing.md),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final heroTag = CatalogCard.heroTagFor(item);
                  return SizedBox(
                    width: 138,
                    child: CatalogCard(
                      item: item,
                      heroTag: heroTag,
                      onTap: () => onOpenCatalog(item, heroTag: heroTag),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// TV 海报货架：更大卡宽、逐项 D-pad 焦点与离屏滚动交接。
class _TvCatalogShelf extends StatefulWidget {
  const _TvCatalogShelf({
    required this.items,
    required this.onOpenCatalog,
    this.entryFocusId,
    this.onEntryFocused,
  });

  final List<CatalogItem> items;
  final CatalogOpenCallback onOpenCatalog;
  final String? entryFocusId;
  final VoidCallback? onEntryFocused;

  @override
  State<_TvCatalogShelf> createState() => _TvCatalogShelfState();
}

class _TvCatalogShelfState extends State<_TvCatalogShelf> {
  final _scroll = ScrollController();
  TvListReveal? _reveal;
  List<String>? _ids;
  Map<String, int> _itemIndices = const {};

  /// 540dp 电视画布上，海报加标题必须能完整落在首屏。
  static const _cardWidth = 140.0;

  @override
  void didUpdateWidget(_TvCatalogShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据刷新后重建 id 表；集合以列表同一性判断数据变化。
    if (!identical(oldWidget.items, widget.items)) _ids = null;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reveal = _reveal ??= TvListReveal.linear(
      controller: _scroll,
      stepExtent: _cardWidth + LumaTvLayout.cardSpacing,
    );
    var ids = _ids;
    if (ids == null) {
      ids = [for (final item in widget.items.take(12)) item.id];
      _ids = ids;
      _itemIndices = {
        for (var index = 0; index < ids.length; index++) ids[index]: index,
      };
    }
    return TvFocusCollection(
      itemIds: ids,
      axis: Axis.horizontal,
      columns: 1,
      revealIndex: reveal.revealIndex,
      child: SizedBox(
        height:
            _cardWidth * 1.5 +
            MediaCard.textDetailsHeight(context, titleLines: 1),
        child: ListView.separated(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(
            horizontal: LumaLayout.pagePaddingH,
          ),
          scrollDirection: Axis.horizontal,
          itemCount: ids.length,
          findItemIndexCallback: (key) =>
              key is ValueKey<String> ? _itemIndices[key.value] : null,
          separatorBuilder: (_, _) =>
              const SizedBox(width: LumaTvLayout.cardSpacing),
          itemBuilder: (context, index) {
            final item = widget.items[index];
            final captureEntry = widget.entryFocusId == item.id;
            return SizedBox(
              key: ValueKey(item.id),
              width: _cardWidth,
              child: CatalogCard(
                item: item,
                // TV 不使用 Hero；路由侧会再次丢弃标签。
                focusId: item.id,
                autofocus: captureEntry,
                focusBorderWidth: LumaTvLayout.focusStroke,
                onTap: () => widget.onOpenCatalog(item),
                onFocusChange: (focused) {
                  if (!focused) return;
                  reveal.track(index);
                  if (captureEntry) widget.onEntryFocused?.call();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// TV 个人视频预览网格：盒式自持焦点集合，滚动基准用页面纵向滚动。
/// 固定六项（SliverToBoxAdapter 常驻构建），不与货架集合嵌套。
class _TvPersonalPreviewGrid extends StatefulWidget {
  const _TvPersonalPreviewGrid({
    required this.items,
    required this.onOpenPersonalMedia,
    required this.scrollController,
    this.entryFocusId,
    this.onEntryFocused,
  });

  final List<MediaItem> items;
  final MediaOpenCallback onOpenPersonalMedia;
  final ScrollController scrollController;
  final String? entryFocusId;
  final VoidCallback? onEntryFocused;

  @override
  State<_TvPersonalPreviewGrid> createState() => _TvPersonalPreviewGridState();
}

class _TvPersonalPreviewGridState extends State<_TvPersonalPreviewGrid> {
  TvGridReveal? _reveal;
  List<String>? _ids;

  @override
  void didUpdateWidget(_TvPersonalPreviewGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据刷新后重建 id 表；集合以列表同一性判断数据变化。
    if (!identical(oldWidget.items, widget.items)) _ids = null;
  }

  @override
  Widget build(BuildContext context) {
    final reveal = _reveal ??= TvGridReveal(
      controller: widget.scrollController,
    );
    final ids = _ids ??= [for (final item in widget.items) item.id];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = const TvMediaGridGeometry().columnsFor(
          constraints.maxWidth,
        );
        return TvFocusCollection(
          itemIds: ids,
          axis: Axis.vertical,
          columns: columns,
          revealIndex: reveal.revealIndex,
          child: TvMediaGrid(
            items: widget.items,
            onTap: widget.onOpenPersonalMedia,
            reveal: reveal,
            entryFocusId: widget.entryFocusId,
            onEntryFocused: widget.onEntryFocused,
          ),
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.onOpenAll});

  final String title;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: LumaLayout.pagePaddingH),
    child: SectionHeader(
      title: title,
      action: TextButton(
        onPressed: onOpenAll,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('查看全部'), Icon(Icons.chevron_right_rounded)],
        ),
      ),
    ),
  );
}
