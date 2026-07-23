import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'widgets/adaptive_app_navigation.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) => AdaptiveAppNavigation(
    selectedIndex: navigationShell.currentIndex,
    onSelect: (index) => navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    ),
    content: navigationShell,
  );
}
