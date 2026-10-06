// TV 规则网格与货架：统一列数/行高计算、卡内 focusId 注册与离屏目标滚动。
// 仅 TV 呈现分支使用；普通端继续使用 ResponsiveMediaGrid 与瀑布流组件。
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import 'media_actions.dart';
import 'media_card.dart';

/// TvListReveal 供页面实现 TvFocusCollection.revealIndex：
/// 记录同一焦点时刻的索引与滚动偏移，连续 reveal 不累加已移动的距离。
/// 卡片聚焦时由货架回调 [track]，移动交接时集合调用 [revealIndex]。
class TvListReveal {
  /// 线性列表/货架：卡宽加间距为步长，横向或纵向单列均适用。
  TvListReveal.linear({required this.controller, required double stepExtent})
    : offsetOf = ((int index) => index * stepExtent);

  /// 自定义偏移表（如含季标题的剧集列表）；两项都从同一张表取值。
  TvListReveal.offsets({required this.controller, required this.offsetOf});

  final ScrollController controller;
  final double Function(int index) offsetOf;

  int _lastIndex = 0;
  double _anchorOffset = 0;

  /// 焦点落在第 [index] 项时更新基准，快速移动多项也以最新值为准。
  void track(int index) {
    _lastIndex = index;
    _anchorOffset = controller.hasClients ? controller.position.pixels : 0;
  }

  /// 把目标项滚进可构建区域；超界时钳制在滚动范围内。
  Future<void> revealIndex(int target) async {
    if (!controller.hasClients) return;
    final position = controller.position;
    final delta = offsetOf(target) - offsetOf(_lastIndex);
    final destination = (_anchorOffset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((destination - position.pixels).abs() < 0.5) return;
    controller.jumpTo(destination);
  }
}

/// 网格几何接口：列数与行高计算，供滚动基准与网格委托共用同一实现。
abstract interface class TvGridMetrics {
  int columnsFor(double width);

  double rowExtentFor(double width);
}

/// 规则网格的滚动基准：列数随局部宽度变化，宽度在卡片聚焦时同步。
class TvGridReveal {
  TvGridReveal({
    required this.controller,
    this.metrics = const TvMediaGridGeometry(),
  });

  final ScrollController controller;

  /// 网格几何；海报网格可传入自己的列数/行高实现。
  TvGridMetrics metrics;

  double? _width;
  int _lastIndex = 0;
  double _anchorOffset = 0;

  /// 焦点落在第 [index] 张卡（局部宽度 [width]）时同步基准。
  void track(int index, double width) {
    _width = width;
    _lastIndex = index;
    _anchorOffset = controller.hasClients ? controller.position.pixels : 0;
  }

  Future<void> revealIndex(int target) async {
    final width = _width;
    if (width == null || !controller.hasClients) return;
    final columns = metrics.columnsFor(width);
    final rowExtent = metrics.rowExtentFor(width);
    final delta = (target ~/ columns - _lastIndex ~/ columns) * rowExtent;
    final position = controller.position;
    final destination = (_anchorOffset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((destination - position.pixels).abs() < 0.5) return;
    controller.jumpTo(destination);
  }
}

/// TV 网格几何：列数与行高共用一套计算，保证委托与 reveal 偏移一致。
class TvMediaGridGeometry implements TvGridMetrics {
  const TvMediaGridGeometry({this.detailsHeight = 96});

  /// 按当前字体与缩放分配两行标题和一行元数据。
  factory TvMediaGridGeometry.of(BuildContext context) =>
      TvMediaGridGeometry(detailsHeight: MediaCard.textDetailsHeight(context));

  final double detailsHeight;

  @override
  int columnsFor(double width) => LumaTvLayout.gridColumns(
    width,
    minItemWidth: LumaTvLayout.landscapeCardMinWidth,
  );

  /// 单元格高度按 16:9 封面与文字区计算，滚动步长额外计入纵向间距。
  @override
  double rowExtentFor(double width) {
    final columns = columnsFor(width);
    final cellWidth =
        (width - LumaTvLayout.cardSpacing * (columns - 1)) / columns;
    return cellWidth / (16 / 9) + detailsHeight + LumaTvLayout.cardSpacing;
  }

  double cellAspectRatio(double width) {
    final columns = columnsFor(width);
    final cellWidth =
        (width - LumaTvLayout.cardSpacing * (columns - 1)) / columns;
    return cellWidth / (cellWidth / (16 / 9) + detailsHeight);
  }
}

/// 用于 CustomScrollView 的 TV 媒体网格：规则列数、固定行高、focusId 注册。
/// 收藏走详情可见按钮，TV 网格不渲染封面覆盖按钮。
class TvMediaSliverGrid extends StatelessWidget {
  const TvMediaSliverGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.onFavorite,
    this.artworkFit,
    this.reveal,
    this.firstItemFocusNode,
  });

  final List<MediaItem> items;
  final MediaOpenCallback onTap;
  final ValueChanged<MediaItem>? onFavorite;

  /// 图片库传 BoxFit.contain 统一画框；视频沿用默认封面填充。
  final BoxFit? artworkFit;

  /// 页面持有的滚动基准；为空时不参与滚动交接（如固定六项的小网格）。
  final TvGridReveal? reveal;

  /// 附加到首卡的焦点节点；搜索页提交后聚焦首个结果时使用。
  final FocusNode? firstItemFocusNode;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final metrics = TvMediaGridGeometry.of(context);
        reveal?.metrics = metrics;
        return SliverGrid.builder(
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metrics.columnsFor(width),
            crossAxisSpacing: LumaTvLayout.cardSpacing,
            mainAxisSpacing: LumaTvLayout.cardSpacing,
            childAspectRatio: metrics.cellAspectRatio(width),
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return MediaCard(
              key: ValueKey(item.id),
              item: item,
              onTap: () => onTap(item),
              focusId: item.id,
              focusBorderWidth: LumaTvLayout.focusStroke,
              focusNode: index == 0 ? firstItemFocusNode : null,
              artworkFit: artworkFit,
              onFocusChange: (focused) {
                if (focused) reveal?.track(index, width);
              },
            );
          },
        );
      },
    );
  }
}

/// 非滚动容器内使用的 TV 媒体网格（如首页“最近添加”分区的 shrinkWrap 网格）。
class TvMediaGrid extends StatelessWidget {
  const TvMediaGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.onFavorite,
    this.artworkFit,
    this.reveal,
  });

  final List<MediaItem> items;
  final MediaOpenCallback onTap;
  final ValueChanged<MediaItem>? onFavorite;
  final BoxFit? artworkFit;
  final TvGridReveal? reveal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final metrics = TvMediaGridGeometry.of(context);
        reveal?.metrics = metrics;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metrics.columnsFor(width),
            crossAxisSpacing: LumaTvLayout.cardSpacing,
            mainAxisSpacing: LumaTvLayout.cardSpacing,
            childAspectRatio: metrics.cellAspectRatio(width),
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return MediaCard(
              key: ValueKey(item.id),
              item: item,
              onTap: () => onTap(item),
              focusId: item.id,
              focusBorderWidth: LumaTvLayout.focusStroke,
              artworkFit: artworkFit,
              onFocusChange: (focused) {
                if (focused) reveal?.track(index, width);
              },
            );
          },
        );
      },
    );
  }
}
