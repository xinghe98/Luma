// 搜索是隐藏分支：壳层注入「关闭搜索」回调，供搜索页在返回时回到
// 进入搜索前的主目的地；仅非 TV 分支注入，TV 仍用遥控器返回层级。
import 'package:flutter/material.dart';

/// 为搜索分支提供关闭回调的作用域；close 时切回最近访问的主目的地分支。
class SearchReturnScope extends InheritedWidget {
  const SearchReturnScope({
    super.key,
    required this.close,
    required super.child,
  });

  /// 关闭搜索分支并回到进入搜索前的最后一个主目的地。
  final VoidCallback close;

  /// 向上查找最近的 SearchReturnScope；不在壳层内时返回 null。
  static SearchReturnScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SearchReturnScope>();

  @override
  bool updateShouldNotify(SearchReturnScope oldWidget) =>
      close != oldWidget.close;
}
