// 首页普通端的版心计算：顶栏、继续观看、货架与网格共用同一左右留白，
// 宽屏最大化时各区块左边缘对齐，不会一部分贴左、一部分居中。TV 首页不使用。
import '../../../core/theme.dart';

abstract final class HomeLayout {
  /// 按区块可用宽度返回左右留白：页面边距，加上超出 [LumaLayout.contentMaxWidth] 后的居中余量。
  static double sideInset(double width) {
    final padding = LumaLayout.pageHorizontalPadding(width);
    final extra = (width - LumaLayout.contentMaxWidth - padding * 2) / 2;
    return extra > 0 ? padding + extra : padding;
  }

  /// 扣除左右留白后的版心宽度。
  static double contentWidth(double width) => width - sideInset(width) * 2;

  /// 宽屏货架卡片宽度：与「最近添加」网格同列宽，换行与横滑的卡片大小一致。
  static double shelfCardWidth(double contentWidth) {
    final columns = LumaLayout.gridColumns(contentWidth);
    return (contentWidth - (columns - 1) * LumaSpacing.md) / columns;
  }
}
