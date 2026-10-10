// 宽屏侧栏：品牌标识在顶，内容目的地依次排列，设置固定在底部。
// 与手机底栏共用 NavigationItem 与滑动胶囊，胶囊纵向滑动；宽于 extended 断点时
// 展开为图标与文字同行。由 AdaptiveAppNavigation 按可用宽度挂载，不按平台判断。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';
import '../app_destination.dart';
import 'navigation_item.dart';

/// 品牌区高度与条目几何；收起态图标在上、文字在下，展开态单行。
const _brandHeight = 72.0;
const _compactItemHeight = 64.0;
const _compactCapsule = Size(56, 32);
const _extendedItemHeight = 56.0;
const _extendedCapsuleHeight = 48.0;

/// 宽屏侧栏导航；[extended] 为 true 时宽度展开并在胶囊内显示文字。
///
/// [selectedIndex] 与 [onSelect] 使用分支序号；搜索分支没有条目，此时不画胶囊。
/// 条目可经 Tab 获得焦点，Enter/Space 激活；不触发轻触感。
class AppNavigationRail extends StatefulWidget {
  const AppNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.extended,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool extended;

  @override
  State<AppNavigationRail> createState() => _AppNavigationRailState();
}

class _AppNavigationRailState extends State<AppNavigationRail>
    with DeferredNavigationSelection<AppNavigationRail> {
  @override
  int get selectedBranch => widget.selectedIndex;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = LumaMotion.forContext(context, LumaMotion.navigation);
    final destinations = AppDestination.primaryDestinations;
    final visualSlot = AppDestination.primaryIndexOf(visualBranch);
    final semanticSlot = AppDestination.primaryIndexOf(widget.selectedIndex);
    final extended = widget.extended;
    final width = extended
        ? LumaLayout.navigationRailExtendedWidth
        : LumaLayout.navigationRailWidth;
    final itemHeight = extended ? _extendedItemHeight : _compactItemHeight;
    final capsule = extended
        ? Rect.fromLTWH(
            LumaSpacing.sm,
            (itemHeight - _extendedCapsuleHeight) / 2,
            width - LumaSpacing.sm * 2,
            _extendedCapsuleHeight,
          )
        : Rect.fromLTWH(
            (width - _compactCapsule.width) / 2,
            LumaSpacing.xs - 2,
            _compactCapsule.width,
            _compactCapsule.height,
          );

    return DecoratedBox(
      key: const ValueKey('rail-navigation-surface'),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: SizedBox(
        width: width,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 设置固定在底部；高度不足时紧跟上方条目，不与其重叠。
            final topCount = destinations.length - 1;
            final topStart = _brandHeight + LumaSpacing.xs;
            final bottomTop = math.max(
              constraints.maxHeight - LumaSpacing.md - itemHeight,
              topStart + topCount * itemHeight,
            );
            final itemTops = [
              for (var i = 0; i < topCount; i++) topStart + i * itemHeight,
              bottomTop,
            ];
            final slotCapsules = [
              for (final top in itemTops) capsule.shift(Offset(0, top)),
            ];
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _brandHeight,
                  child: Align(
                    alignment: extended
                        ? const AlignmentDirectional(-1, 0)
                        : Alignment.center,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: extended ? LumaSpacing.lg : 0,
                      ),
                      child: BrandMark(
                        variant: extended
                            ? BrandMarkVariant.horizontal
                            : BrandMarkVariant.symbol,
                        compact: true,
                        height: extended ? 28 : 32,
                      ),
                    ),
                  ),
                ),
                if (visualSlot != null)
                  TweenAnimationBuilder<double>(
                    key: const ValueKey('rail-navigation-indicator-animation'),
                    tween: Tween(end: visualSlot.toDouble()),
                    duration: duration,
                    curve: LumaMotion.standard,
                    builder: (context, value, child) => Positioned.fromRect(
                      rect: lerpNavigationSlots(slotCapsules, value),
                      child: child!,
                    ),
                    child: const NavigationCapsule(
                      key: ValueKey('rail-navigation-indicator'),
                    ),
                  ),
                for (final (slot, destination) in destinations.indexed)
                  Positioned(
                    key: ValueKey('rail-nav-slot-${destination.routeName}'),
                    left: 0,
                    top: itemTops[slot],
                    width: width,
                    height: itemHeight,
                    child: NavigationItem(
                      semanticsKey: ValueKey(
                        'rail-nav-${destination.routeName}',
                      ),
                      destination: destination,
                      layout: extended
                          ? NavigationItemLayout.inline
                          : NavigationItemLayout.stacked,
                      capsule: capsule,
                      selected: slot == visualSlot,
                      semanticallySelected: slot == semanticSlot,
                      onTap: () => widget.onSelect(destination.index),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
