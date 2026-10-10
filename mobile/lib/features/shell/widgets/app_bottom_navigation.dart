// 窄屏贴底导航栏：四个主目的地平分宽度，选中项背后的淡胶囊横向滑动。
// 由 AdaptiveAppNavigation 在窄于 Rail 断点时挂载；搜索是隐藏分支，不占槽位。
// 选中动画经 DeferredNavigationSelection 推迟一帧，先让目标分支完成首帧。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../app_destination.dart';
import 'navigation_item.dart';

/// 胶囊外观尺寸：高度与图标留白固定，宽度在窄槽位里收缩。
const _capsuleHeight = 32.0;
const _capsuleMaxWidth = 64.0;
const _capsuleTop = 8.0;

/// 手机底部导航；[selectedIndex] 与 [onSelect] 使用分支序号而非槽位序号。
///
/// 切换到新分支时触发轻触感，重复点击当前分支只回调 [onSelect]，由路由回到根页。
class AppBottomNavigation extends StatefulWidget {
  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  State<AppBottomNavigation> createState() => _AppBottomNavigationState();
}

class _AppBottomNavigationState extends State<AppBottomNavigation>
    with DeferredNavigationSelection<AppBottomNavigation> {
  @override
  int get selectedBranch => widget.selectedIndex;

  void _handleSelect(int index) {
    if (index != widget.selectedIndex) {
      unawaited(HapticFeedback.selectionClick());
    }
    widget.onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = LumaMotion.forContext(context, LumaMotion.navigation);
    final destinations = AppDestination.primaryDestinations;
    final visualSlot = AppDestination.primaryIndexOf(visualBranch);
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
                final slotWidth = constraints.maxWidth / destinations.length;
                final capsuleWidth = (slotWidth - LumaSpacing.xs).clamp(
                  0.0,
                  _capsuleMaxWidth,
                );
                final capsule = Rect.fromLTWH(
                  (slotWidth - capsuleWidth) / 2,
                  _capsuleTop,
                  capsuleWidth,
                  _capsuleHeight,
                );
                final slotCapsules = [
                  for (var i = 0; i < destinations.length; i++)
                    capsule.shift(Offset(i * slotWidth, 0)),
                ];
                return Stack(
                  children: [
                    if (visualSlot != null)
                      TweenAnimationBuilder<double>(
                        key: const ValueKey(
                          'bottom-navigation-indicator-animation',
                        ),
                        tween: Tween(end: visualSlot.toDouble()),
                        duration: duration,
                        curve: LumaMotion.standard,
                        builder: (context, value, child) => Positioned.fromRect(
                          rect: lerpNavigationSlots(slotCapsules, value),
                          child: child!,
                        ),
                        child: const NavigationCapsule(
                          key: ValueKey('bottom-navigation-indicator'),
                        ),
                      ),
                    for (final (slot, destination) in destinations.indexed)
                      Positioned(
                        key: ValueKey(
                          'bottom-nav-slot-${destination.routeName}',
                        ),
                        left: slot * slotWidth,
                        top: 0,
                        bottom: 0,
                        width: slotWidth,
                        child: NavigationItem(
                          semanticsKey: ValueKey(
                            'bottom-nav-${destination.routeName}',
                          ),
                          destination: destination,
                          layout: NavigationItemLayout.stacked,
                          capsule: capsule,
                          selected: slot == visualSlot,
                          semanticallySelected: slot == semanticSlot,
                          onTap: () => _handleSelect(destination.index),
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
