import 'package:flutter/material.dart';

enum AppDestination {
  home(
    label: '首页',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  photos(
    label: '图片库',
    icon: Icons.photo_library_outlined,
    selectedIcon: Icons.photo_library_rounded,
  ),
  videos(
    label: '影音库',
    icon: Icons.movie_outlined,
    selectedIcon: Icons.movie_rounded,
  ),
  search(
    label: '搜索',
    icon: Icons.search_rounded,
    selectedIcon: Icons.search_rounded,
  ),
  settings(
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  );

  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  NavigationDestination toNavigationDestination() => NavigationDestination(
    icon: Icon(icon),
    selectedIcon: Icon(selectedIcon),
    label: label,
  );

  NavigationRailDestination toNavigationRailDestination() =>
      NavigationRailDestination(
        icon: Icon(icon),
        selectedIcon: Icon(selectedIcon),
        label: Text(label),
      );
}
