import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';
import '../app_destination.dart';
import 'tv_app_navigation.dart';

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

  /// TV 使用左侧常驻导航；手机底部导航与宽屏 Rail 分支保持不变。
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
            bottomNavigationBar: _LumaBottomNavigation(
              selectedIndex: selectedIndex,
              onSelect: onSelect,
            ),
          );
        }
        final extended =
            constraints.maxWidth >= LumaLayout.extendedRailBreakpoint;
        // 槽位序号与主目的地序号之间的换算：search 分支没有槽位，选中序号为 null。
        final primaryDestinations = AppDestination.primaryDestinations;
        final primaryIndex = AppDestination.primaryIndexOf(selectedIndex);
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  extended: extended,
                  selectedIndex: primaryIndex,
                  onDestinationSelected: (index) =>
                      onSelect(primaryDestinations[index].index),
                  // 搜索入口由各页顶栏的搜索图标和 Ctrl+F 提供，Rail 只放品牌标识。
                  leading: const Padding(
                    padding: EdgeInsets.only(bottom: LumaSpacing.sm),
                    child: BrandMark(
                      variant: BrandMarkVariant.symbol,
                      compact: true,
                      height: 32,
                    ),
                  ),
                  destinations: primaryDestinations
                      .map((item) => item.toNavigationRailDestination())
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LumaBottomNavigation extends StatefulWidget {
  const _LumaBottomNavigation({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  State<_LumaBottomNavigation> createState() => _LumaBottomNavigationState();
}

class _LumaBottomNavigationState extends State<_LumaBottomNavigation> {
  late int _visualIndex;
  int? _scheduledIndex;

  @override
  void initState() {
    super.initState();
    _visualIndex = widget.selectedIndex;
  }

  @override
  void didUpdateWidget(_LumaBottomNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != _visualIndex &&
        widget.selectedIndex != _scheduledIndex) {
      _scheduleVisualIndex(widget.selectedIndex);
    }
  }

  /// 先提交目标分支首帧，再启动导航动画，避免首次构建挤占动画帧预算。
  void _scheduleVisualIndex(int index) {
    _scheduledIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scheduledIndex != index) return;
      _scheduledIndex = null;
      if (widget.selectedIndex != index) {
        if (widget.selectedIndex != _visualIndex) {
          _scheduleVisualIndex(widget.selectedIndex);
        }
        return;
      }
      setState(() => _visualIndex = index);
    });
  }

  /// 切换新分支时提供轻触感；重复当前分支仍交给路由处理回到根页。
  void _handleSelect(int index) {
    if (index != widget.selectedIndex) {
      unawaited(HapticFeedback.selectionClick());
    }
    widget.onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final duration = LumaMotion.forContext(context, LumaMotion.navigation);
    // 搜索是隐藏分支：没有槽位，不画指示器，全部槽位按未选中显示。
    final visualSlot = AppDestination.primaryIndexOf(_visualIndex);
    final semanticSlot = AppDestination.primaryIndexOf(widget.selectedIndex);
    return ColoredBox(
      color: colors.surfaceContainer,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          key: const ValueKey('bottom-navigation-surface'),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: SizedBox(
            height: LumaLayout.navigationBarHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final primaryDestinations = AppDestination.primaryDestinations;
                final slotWidth =
                    constraints.maxWidth / primaryDestinations.length;
                return Stack(
                  children: [
                    // 顶部指示器按槽位横向滑动；隐藏分支上停用时全部移除。
                    if (visualSlot != null)
                      Positioned(
                        left: (slotWidth - _bottomNavIndicatorWidth) / 2,
                        top: 0,
                        width: _bottomNavIndicatorWidth,
                        height: _bottomNavIndicatorHeight,
                        child: TweenAnimationBuilder<double>(
                          key: const ValueKey(
                            'bottom-navigation-indicator-animation',
                          ),
                          tween: Tween(end: visualSlot.toDouble()),
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) =>
                              Transform.translate(
                                key: const ValueKey(
                                  'bottom-navigation-indicator',
                                ),
                                offset: Offset(value * slotWidth, 0),
                                child: child,
                              ),
                          child: RepaintBoundary(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(
                                  LumaRadii.badge,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    for (final entry in primaryDestinations.indexed)
                      Positioned(
                        key: ValueKey('bottom-nav-slot-${entry.$2.routeName}'),
                        left: entry.$1 * slotWidth,
                        top: 0,
                        bottom: 0,
                        width: slotWidth,
                        child: _BottomDestination(
                          destination: entry.$2,
                          selected: entry.$1 == visualSlot,
                          semanticallySelected: entry.$1 == semanticSlot,
                          activeColor: colors.primary,
                          inactiveColor: colors.onSurfaceVariant,
                          textTheme: textTheme,
                          onTap: () => _handleSelect(entry.$2.index),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// 底栏指示器：位于槽位顶部的胶囊横条。
const _bottomNavIndicatorWidth = 24.0;
const _bottomNavIndicatorHeight = 3.0;

/// 底栏单个槽位：图标在上、标签在下，始终同时显示。
class _BottomDestination extends StatelessWidget {
  const _BottomDestination({
    required this.destination,
    required this.selected,
    required this.semanticallySelected,
    required this.activeColor,
    required this.inactiveColor,
    required this.textTheme,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final bool semanticallySelected;
  final Color activeColor;
  final Color inactiveColor;
  final TextTheme textTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    final textStyle = textTheme.labelMedium?.copyWith(
      color: color,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      height: 1.2,
    );
    return Semantics(
      key: ValueKey('bottom-nav-${destination.routeName}'),
      button: true,
      selected: semanticallySelected,
      label: destination.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: color,
                size: LumaIconSize.action,
              ),
              const SizedBox(height: LumaSpacing.xxs),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: textStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
