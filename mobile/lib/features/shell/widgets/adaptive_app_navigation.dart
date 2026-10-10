// 普通端与 TV 导航的分派入口：TV 走焦点驱动侧栏，其他设备按可用宽度选择
// 手机底栏或宽屏侧栏。两种普通端导航共用滑动胶囊视觉与同一份目的地数据。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import 'app_bottom_navigation.dart';
import 'app_navigation_rail.dart';
import 'tv_app_navigation.dart';

/// 按设备形态与可用宽度挂载导航，并把 [content] 放进剩余区域。
///
/// [selectedIndex] 与 [onSelect] 使用分支序号；搜索分支没有导航槽位。
class AdaptiveAppNavigation extends StatelessWidget {
  const AdaptiveAppNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.content,
    this.isTelevision = false,
    this.focusContentOnStart = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget content;

  /// TV 使用左侧焦点导航；普通端按宽度在底栏与侧栏之间切换。
  final bool isTelevision;

  /// 电视首次进入时收起导航并浏览内容；手机和桌面忽略。
  final bool focusContentOnStart;

  @override
  Widget build(BuildContext context) {
    if (isTelevision) {
      return TvAppNavigation(
        selectedIndex: selectedIndex,
        onSelect: onSelect,
        content: content,
        focusContentOnStart: focusContentOnStart,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < LumaLayout.navigationRailBreakpoint) {
          return Scaffold(
            body: content,
            bottomNavigationBar: AppBottomNavigation(
              selectedIndex: selectedIndex,
              onSelect: onSelect,
            ),
          );
        }
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                AppNavigationRail(
                  selectedIndex: selectedIndex,
                  onSelect: onSelect,
                  extended:
                      constraints.maxWidth >= LumaLayout.extendedRailBreakpoint,
                ),
                Expanded(child: content),
              ],
            ),
          ),
        );
      },
    );
  }
}
