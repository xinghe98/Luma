// 导航分支容器：由 go_router 的当前分支决定显示、动画与焦点隔离。
// 根层详情覆盖期间保留来源分支的焦点历史；各 Navigator 的生命周期仍由路由管理。
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 保留各分支页面状态，仅排除未选分支的焦点，不把路由遮盖当成分支切换。
Widget buildBranchNavigatorContainer(
  BuildContext context,
  StatefulNavigationShell shell,
  List<Widget> children,
) => IndexedStack(
  index: shell.currentIndex,
  children: [
    for (var index = 0; index < children.length; index++)
      Offstage(
        offstage: index != shell.currentIndex,
        child: TickerMode(
          enabled: index == shell.currentIndex,
          child: ExcludeFocus(
            excluding: index != shell.currentIndex,
            child: children[index],
          ),
        ),
      ),
  ],
);
