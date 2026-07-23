import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';
import '../app_destination.dart';

class AdaptiveAppNavigation extends StatelessWidget {
  const AdaptiveAppNavigation({
    super.key,
    required this.destination,
    required this.onSelect,
    required this.content,
  });

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < LumaLayout.navigationRailBreakpoint) {
          return Scaffold(
            body: content,
            bottomNavigationBar: NavigationBar(
              animationDuration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : LumaMotion.normal,
              selectedIndex: destination.index,
              onDestinationSelected: (index) =>
                  onSelect(AppDestination.values[index]),
              destinations: AppDestination.values
                  .map((item) => item.toNavigationDestination())
                  .toList(),
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
                  selectedIndex: destination.index,
                  onDestinationSelected: (index) =>
                      onSelect(AppDestination.values[index]),
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
