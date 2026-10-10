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
                  LumaSpacing.xs +
                  CatalogCard.textDetailsHeight(context),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = LumaLayout.posterShelfWidth(constraints.maxWidth);
          final shelfHeight =
              cardWidth * 1.5 +
              LumaSpacing.xs +
              CatalogCard.textDetailsHeight(context);
          final visibleCards = (constraints.maxWidth / cardWidth).ceil().clamp(
            2,
            8,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeading(title: title, onOpenAll: onOpenAll),
              const SizedBox(height: LumaSpacing.md),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LumaLayout.pagePaddingH,
                ),
                child: SizedBox(
                  height: shelfHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visibleCards,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: LumaSpacing.md),
                    itemBuilder: (_, _) => SizedBox(
                      width: cardWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            height: cardWidth * 1.5,
                            radius: LumaRadii.cover,
                          ),
                          const SizedBox(height: LumaSpacing.sm),
                          const SkeletonBox(height: 18, width: 96),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = LumaLayout.posterShelfWidth(constraints.maxWidth);
            return SizedBox(
              height:
                  cardWidth * 1.5 +
                  LumaSpacing.xs +
                  CatalogCard.textDetailsHeight(context),
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
            );
          },
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

class _CatalogShelf extends StatefulWidget {
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
  State<_CatalogShelf> createState() => _CatalogShelfState();
}

class _CatalogShelfState extends State<_CatalogShelf> {
  final _scroll = ScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncScrollActions);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollActions());
  }

  @override
  void didUpdateWidget(_CatalogShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollActions());
    }
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_syncScrollActions)
      ..dispose();
    super.dispose();
  }

  void _syncScrollActions() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final back = position.pixels > position.minScrollExtent + 1;
    final forward = position.pixels < position.maxScrollExtent - 1;
    if (back == _canScrollBack && forward == _canScrollForward) return;
    setState(() {
      _canScrollBack = back;
      _canScrollForward = forward;
    });
  }

  /// 按当前可视宽度翻动货架，与首页媒体货架同一翻页比例。
  void _scrollBy(int direction) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target =
        position.pixels + position.viewportDimension * 0.72 * direction;
    _scroll.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: LumaMotion.forContext(context, LumaMotion.normal),
      curve: Curves.easeOutQuart,
    );
  }

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
          LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= LumaLayout.navigationRailBreakpoint;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LumaLayout.pagePaddingH,
                ),
                child: SectionHeader(
                  title: widget.title,
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 与首页货架一致：只在放不下时显示，普通图标按钮不加底色。
                      if (!isTelevision &&
                          wide &&
                          (_canScrollBack || _canScrollForward)) ...[
                        IconButton(
                          tooltip: '向左翻页',
                          onPressed: _canScrollBack
                              ? () => _scrollBy(-1)
                              : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        IconButton(
                          tooltip: '向右翻页',
                          onPressed: _canScrollForward
                              ? () => _scrollBy(1)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                        const SizedBox(width: LumaSpacing.xs),
                      ],
                      TextButton(
                        onPressed: widget.onOpenAll,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('查看全部'),
                            Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (widget.loading)
            const Padding(
              padding: EdgeInsets.only(top: LumaSpacing.xs),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (widget.hasError)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LumaLayout.pagePaddingH,
                ),
                child: TextButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新失败，当前保留上次内容'),
                ),
              ),
            ),
          const SizedBox(height: LumaSpacing.md),
          // TV：大海报货架与逐项焦点；触控端保持既有小卡与箭头-free 横滑。
          if (isTelevision)
            _TvCatalogShelf(
              items: widget.items,
              onOpenCatalog: widget.onOpenCatalog,
              entryFocusId: widget.entryFocusId,
              onEntryFocused: widget.onEntryFocused,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = LumaLayout.posterShelfWidth(
                  constraints.maxWidth,
                );
                final shelfHeight =
                    cardWidth * 1.5 +
                    LumaSpacing.xs +
                    CatalogCard.textDetailsHeight(context);
                return SizedBox(
                  height: shelfHeight,
                  child: ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: LumaLayout.pagePaddingH,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.items.length.clamp(0, 12),
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: LumaSpacing.md),
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final heroTag = CatalogCard.heroTagFor(item);
                      return SizedBox(
                        width: cardWidth,
                        child: CatalogCard(
                          item: item,
                          heroTag: heroTag,
                          onTap: () =>
                              widget.onOpenCatalog(item, heroTag: heroTag),
                        ),
                      );
                    },
                  ),
                );
              },
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
