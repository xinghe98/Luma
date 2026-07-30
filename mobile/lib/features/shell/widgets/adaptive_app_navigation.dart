import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';
import '../app_destination.dart';

class AdaptiveAppNavigation extends StatelessWidget {
  const AdaptiveAppNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.content,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget content;

  @override
  Widget build(BuildContext context) {
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
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  extended: extended,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelect,
                  leading: const Padding(
                    padding: EdgeInsets.only(bottom: LumaSpacing.lg),
                    child: BrandMark(
                      variant: BrandMarkVariant.symbol,
                      compact: true,
                      height: 36,
                    ),
                  ),
                  destinations: AppDestination.values
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final duration = LumaMotion.forContext(context, LumaMotion.navigation);
    final compact = MediaQuery.sizeOf(context).width < 360;
    final horizontalMargin = compact ? LumaSpacing.xs : LumaSpacing.md;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(
          horizontalMargin,
          LumaSpacing.xxs,
          horizontalMargin,
          LumaSpacing.xs,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: RepaintBoundary(
              child: DecoratedBox(
                key: const ValueKey('bottom-navigation-surface'),
                decoration: BoxDecoration(
                  color: isDark
                      ? colors.surfaceContainerHigh
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(LumaRadii.extraLarge),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(
                      alpha: isDark ? 0.58 : 0.52,
                    ),
                  ),
                ),
                child: SizedBox(
                  height: 64,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final destinationCount = AppDestination.values.length;
                      const trackInset = LumaSpacing.xs;
                      final trackWidth =
                          constraints.maxWidth - trackInset * 2;
                      final slotWidth = trackWidth / destinationCount;
                      final indicatorWidth = (slotWidth + LumaSpacing.xs)
                          .clamp(64.0, 88.0)
                          .toDouble();
                      return Stack(
                        children: [
                          Positioned(
                            left:
                                trackInset +
                                (slotWidth - indicatorWidth) / 2,
                            top: 10,
                            width: indicatorWidth,
                            height: 44,
                            child: TweenAnimationBuilder<double>(
                              key: const ValueKey(
                                'bottom-navigation-indicator-animation',
                              ),
                              tween: Tween(end: _visualIndex.toDouble()),
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
                                      LumaRadii.extraLarge,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          for (final entry in AppDestination.values.indexed)
                            Positioned(
                              key: ValueKey(
                                'bottom-nav-slot-${entry.$2.routeName}',
                              ),
                              left: trackInset + entry.$1 * slotWidth,
                              top: LumaSpacing.xxs,
                              width: slotWidth,
                              height: 56,
                              child: _BottomDestination(
                                destination: entry.$2,
                                selected: entry.$1 == _visualIndex,
                                semanticallySelected:
                                    entry.$1 == widget.selectedIndex,
                                activeColor: colors.onPrimary,
                                inactiveColor: colors.onSurfaceVariant,
                                duration: duration,
                                selectedContentWidth: indicatorWidth,
                                onTap: () => _handleSelect(entry.$1),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomDestination extends StatelessWidget {
  const _BottomDestination({
    required this.destination,
    required this.selected,
    required this.semanticallySelected,
    required this.activeColor,
    required this.inactiveColor,
    required this.duration,
    required this.selectedContentWidth,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final bool semanticallySelected;
  final Color activeColor;
  final Color inactiveColor;
  final Duration duration;
  final double selectedContentWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: color,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1,
    );
    return Semantics(
      key: ValueKey('bottom-nav-${destination.routeName}'),
      button: true,
      selected: semanticallySelected,
      label: destination.label,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: InkWell(
            borderRadius: BorderRadius.circular(LumaRadii.extraLarge),
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: Center(
                child: OverflowBox(
                  maxWidth: selectedContentWidth,
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: Curves.linear,
                    switchOutCurve: Curves.linear,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.center,
                      children: [?currentChild],
                    ),
                    transitionBuilder: (child, animation) {
                      final entrance = CurvedAnimation(
                        parent: animation,
                        curve: const Interval(
                          0.15,
                          1,
                          curve: Curves.easeOutCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: entrance,
                        child: SlideTransition(
                          position:
                              Tween<Offset>(
                                begin: const Offset(0.06, 0),
                                end: Offset.zero,
                              ).animate(entrance),
                          child: child,
                        ),
                      );
                    },
                    child: selected
                        ? Row(
                            key: ValueKey(
                              'bottom-nav-selected-content-${destination.routeName}',
                            ),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                destination.selectedIcon,
                                color: color,
                                size: LumaIconSize.inline,
                              ),
                              const SizedBox(width: LumaSpacing.xxs),
                              Text(
                                destination.label,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: textStyle,
                              ),
                            ],
                          )
                        : Icon(
                            destination.icon,
                            key: const ValueKey('unselected'),
                            color: color,
                            size: LumaIconSize.inline,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
