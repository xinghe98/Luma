import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/media_types.dart';
import '../../../shared/interaction/tv_focus_collection.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/media/media_actions.dart';
import '../../../shared/media/media_card.dart';
import '../../../shared/media/tv_media_grid.dart';

class HorizontalMediaSection extends StatefulWidget {
  /// 显示可触控横滑的媒体货架，并在宽屏提供键盘与箭头翻页。
  const HorizontalMediaSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heroPrefix,
    required this.items,
    required this.onOpenMedia,
    required this.onFavorite,
  });

  final String title;
  final String subtitle;
  final String heroPrefix;
  final List<MediaItem> items;
  final MediaOpenCallback onOpenMedia;
  final ValueChanged<MediaItem> onFavorite;

  @override
  State<HorizontalMediaSection> createState() => _HorizontalMediaSectionState();
}

class _HorizontalMediaSectionState extends State<HorizontalMediaSection> {
  final _scroll = ScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = false;
  TvListReveal? _tvReveal;
  List<String>? _tvItemIds;
  Map<String, int> _tvItemIndices = const {};

  @override
  void didUpdateWidget(covariant HorizontalMediaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) _tvItemIds = null;
    if (oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollActions());
    }
  }

  // 集合以列表同一性判断数据变化；跨重建复用 id 表避免误取消移动交接。
  List<String> get _tvIds {
    var ids = _tvItemIds;
    if (ids == null) {
      ids = [for (final item in widget.items) item.id];
      _tvItemIds = ids;
      _tvItemIndices = {
        for (var index = 0; index < ids.length; index++) ids[index]: index,
      };
    }
    return ids;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncScrollActions);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollActions());
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

  /// 按当前可视宽度翻动货架，并限制在滚动边界内。
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
    if (widget.items.isEmpty) return const SizedBox.shrink();
    // TV：删除整排左右快捷键与翻页箭头，改为逐项焦点货架。
    if (AppScope.of(context).deviceProfile.isTelevision) {
      return _buildTvShelf(context);
    }
    final desktop =
        MediaQuery.sizeOf(context).width >= LumaLayout.navigationRailBreakpoint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LumaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LumaLayout.pagePaddingH,
            ),
            child: SectionHeader(
              title: widget.title,
              subtitle: widget.subtitle,
              action: desktop
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.filledTonal(
                          tooltip: '向左翻页',
                          onPressed: _canScrollBack
                              ? () => _scrollBy(-1)
                              : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        const SizedBox(width: LumaSpacing.xs),
                        IconButton.filledTonal(
                          tooltip: '向右翻页',
                          onPressed: _canScrollForward
                              ? () => _scrollBy(1)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
          const SizedBox(height: LumaSpacing.md),
          CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _scrollBy(-1),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _scrollBy(1),
            },
            child: SizedBox(
              height: MediaCard.heightForWidth(
                LumaLayout.horizontalCardWidth,
                detailsHeight: MediaCard.textDetailsHeight(
                  context,
                  titleLines: 1,
                ),
              ),
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: LumaLayout.pagePaddingH,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: widget.items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: LumaSpacing.md),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final heroTag = item.type == MediaType.video
                      ? null
                      : '${widget.heroPrefix}-${item.id}';
                  return SizedBox(
                    width: LumaLayout.horizontalCardWidth,
                    child: MediaCard(
                      item: item,
                      compact: true,
                      heroTag: heroTag,
                      onTap: () => widget.onOpenMedia(item, heroTag: heroTag),
                      onFavorite: () => widget.onFavorite(item),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// TV 货架：更大横版卡、逐项 D-pad 焦点；首卡向左越界交给
  /// 默认遍历进入左导航，收藏改由详情可见按钮操作。
  Widget _buildTvShelf(BuildContext context) {
    const cardWidth = LumaTvLayout.landscapeCardMinWidth;
    const spacing = LumaTvLayout.cardSpacing;
    final reveal = _tvReveal ??= TvListReveal.linear(
      controller: _scroll,
      stepExtent: cardWidth + spacing,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LumaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LumaLayout.pagePaddingH,
            ),
            child: SectionHeader(
              title: widget.title,
              subtitle: widget.subtitle,
            ),
          ),
          const SizedBox(height: LumaSpacing.md),
          TvFocusCollection(
            itemIds: _tvIds,
            axis: Axis.horizontal,
            columns: 1,
            revealIndex: reveal.revealIndex,
            child: SizedBox(
              height:
                  cardWidth / 1.6 +
                  MediaCard.textDetailsHeight(context, titleLines: 1) +
                  LumaSpacing.xs * 2,
              child: ListView.separated(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: LumaLayout.pagePaddingH,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: widget.items.length,
                findItemIndexCallback: (key) =>
                    key is ValueKey<String> ? _tvItemIndices[key.value] : null,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: LumaTvLayout.cardSpacing),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return SizedBox(
                    key: ValueKey(item.id),
                    width: cardWidth,
                    child: MediaCard(
                      item: item,
                      compact: true,
                      focusId: item.id,
                      focusBorderWidth: LumaTvLayout.focusStroke,
                      onTap: () => widget.onOpenMedia(item),
                      onFocusChange: (focused) {
                        if (focused) reveal.track(index);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
