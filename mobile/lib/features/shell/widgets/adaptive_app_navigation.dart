import 'package:flutter/material.dart';

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

class _LumaBottomNavigation extends StatelessWidget {
  const _LumaBottomNavigation({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = colors.primary;
    final inactiveColor = isDark
        ? LumaColors.onInkMuted
        : colors.onSurfaceVariant;
    final duration = LumaMotion.forContext(context, LumaMotion.normal);
    final surface = isDark ? colors.surfaceDim : colors.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          top: BorderSide(
            color: colors.outlineVariant.withValues(
              alpha: isDark ? 0.62 : 0.72,
            ),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: Row(
            children: AppDestination.values.indexed
                .map(
                  (entry) => Expanded(
                    child: _BottomDestination(
                      destination: entry.$2,
                      selected: entry.$1 == selectedIndex,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                      duration: duration,
                      onTap: () => onSelect(entry.$1),
                    ),
                  ),
                )
                .toList(growable: false),
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
    required this.activeColor,
    required this.inactiveColor,
    required this.duration,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : inactiveColor;
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: color,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      height: 1.15,
    );
    return Semantics(
      key: ValueKey('bottom-nav-${destination.routeName}'),
      button: true,
      selected: selected,
      label: destination.label,
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: InkResponse(
            containedInkWell: true,
            customBorder: const CircleBorder(),
            highlightShape: BoxShape.circle,
            radius: 32,
            splashColor: color.withValues(alpha: 0.14),
            highlightColor: color.withValues(alpha: 0.08),
            hoverColor: color.withValues(alpha: 0.06),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 64,
              child: Center(
                child: AnimatedOpacity(
                  opacity: selected ? 1 : 0.78,
                  duration: duration,
                  curve: LumaMotion.standard,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: LumaMotion.standard,
                        switchOutCurve: LumaMotion.standard,
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: Icon(
                          selected
                              ? destination.selectedIcon
                              : destination.icon,
                          key: ValueKey(selected),
                          color: color,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: LumaSpacing.xs),
                      AnimatedDefaultTextStyle(
                        duration: duration,
                        curve: LumaMotion.standard,
                        style: textStyle ?? const TextStyle(),
                        child: Text(destination.label, maxLines: 1),
                      ),
                    ],
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
