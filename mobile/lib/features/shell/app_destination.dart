import 'package:flutter/material.dart';

enum AppDestination {
  home(
    label: '首页',
    routeName: 'home',
    path: '/home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  videos(
    label: '影视',
    routeName: 'videos',
    path: '/videos',
    icon: Icons.movie_outlined,
    selectedIcon: Icons.movie_rounded,
  ),
  photos(
    label: '照片',
    routeName: 'photos',
    path: '/photos',
    icon: Icons.photo_library_outlined,
    selectedIcon: Icons.photo_library_rounded,
  ),
  search(
    label: '搜索',
    routeName: 'search',
    path: '/search',
    icon: Icons.search_rounded,
    selectedIcon: Icons.search_rounded,
    primary: false,
  ),
  settings(
    label: '设置',
    routeName: 'settings',
    path: '/settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  );

  const AppDestination({
    required this.label,
    required this.routeName,
    required this.path,
    required this.icon,
    required this.selectedIcon,
    this.primary = true,
  });

  final String label;
  final String routeName;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  /// 是否计入底部导航与侧栏的主目的地；搜索是隐藏分支，不占槽位。
  final bool primary;

  /// 主目的地列表，顺序即底栏/侧栏槽位顺序；最后一项（设置）在侧栏固定于底部。
  static final List<AppDestination> primaryDestinations = values
      .where((d) => d.primary)
      .toList(growable: false);

  /// 把分支序号换算成主目的地槽位；隐藏分支（搜索）返回 null。
  static int? primaryIndexOf(int branchIndex) {
    if (branchIndex < 0 || branchIndex >= values.length) return null;
    final destination = values[branchIndex];
    if (!destination.primary) return null;
    return primaryDestinations.indexOf(destination);
  }

  /// 电视冷启动进入影视，手机和桌面仍进入首页。
  static String landingPath({required bool television}) =>
      television ? videos.path : home.path;
}
