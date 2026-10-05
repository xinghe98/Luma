import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/interaction/tv_focus_collection.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/media/media_actions.dart';
import '../../../shared/media/responsive_media_grid.dart';
import '../../../shared/media/tv_media_grid.dart';

class RecentMediaSection extends StatelessWidget {
  const RecentMediaSection({
    super.key,
    required this.items,
    required this.onOpenMedia,
    required this.onFavorite,
    this.scrollController,
  });

  final List<MediaItem> items;
  final MediaOpenCallback onOpenMedia;
  final ValueChanged<MediaItem> onFavorite;

  /// TV 网格复用首页纵向滚动；普通端不传。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final isTelevision = AppScope.of(context).deviceProfile.isTelevision;
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LumaLayout.contentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            LumaLayout.pagePaddingH,
            LumaSpacing.sm,
            LumaLayout.pagePaddingH,
            LumaSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: '最近添加', subtitle: '服务器里新出现的内容'),
              const SizedBox(height: LumaSpacing.md),
              // TV 使用规则网格与逐项焦点；手机/Windows 保持既有网格。
              if (isTelevision && scrollController != null)
                _TvRecentGrid(
                  items: items,
                  onOpenMedia: onOpenMedia,
                  scrollController: scrollController!,
                )
              else
                ResponsiveMediaGrid(
                  items: items,
                  heroTagPrefix: 'recent',
                  onTap: onOpenMedia,
                  onFavorite: onFavorite,
                ),
            ],
          ),
        ),
      ),
    );
    return content;
  }
}

class _TvRecentGrid extends StatefulWidget {
  const _TvRecentGrid({
    required this.items,
    required this.onOpenMedia,
    required this.scrollController,
  });

  final List<MediaItem> items;
  final MediaOpenCallback onOpenMedia;
  final ScrollController scrollController;

  @override
  State<_TvRecentGrid> createState() => _TvRecentGridState();
}

class _TvRecentGridState extends State<_TvRecentGrid> {
  TvGridReveal? _reveal;
  List<String>? _ids;

  @override
  void didUpdateWidget(_TvRecentGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据刷新（列表身份变化）后重建 id 表，保持与可见顺序一致。
    if (!identical(oldWidget.items, widget.items)) _ids = null;
  }

  // itemIds 必须跨重建复用：集合以列表同一性判断数据变化，避免误取消移动。
  List<String> get _itemIds {
    var ids = _ids;
    if (ids == null) {
      ids = [for (final item in widget.items) item.id];
      _ids = ids;
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final reveal = _reveal ??= TvGridReveal(
      controller: widget.scrollController,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = const TvMediaGridGeometry().columnsFor(
          constraints.maxWidth,
        );
        return TvFocusCollection(
          itemIds: _itemIds,
          axis: Axis.vertical,
          columns: columns,
          revealIndex: reveal.revealIndex,
          child: TvMediaGrid(
            items: widget.items,
            onTap: widget.onOpenMedia,
            reveal: reveal,
          ),
        );
      },
    );
  }
}
