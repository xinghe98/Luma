import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../shared/interaction/tv_key_bindings.dart';
import 'app_destination.dart';
import 'widgets/adaptive_app_navigation.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    // TV 差异只读注入的设备能力，不在此探测平台或屏幕尺寸。
    if (AppScope.of(context).deviceProfile.isTelevision) {
      return _TvShell(navigationShell: navigationShell);
    }
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            navigationShell.goBranch(AppDestination.search.index),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: AdaptiveAppNavigation(
          selectedIndex: navigationShell.currentIndex,
          onSelect: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          content: navigationShell,
        ),
      ),
    );
  }
}

/// TV 壳层：确认键映射激活、按焦点展开侧栏、内容区安全边距。
/// 相同分支按 OK 不重置页面；返回层级由 TvAppNavigation 统一处理。
class _TvShell extends StatelessWidget {
  const _TvShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return TvKeyBindings(
      child: AdaptiveAppNavigation(
        isTelevision: true,
        focusContentOnStart:
            navigationShell.currentIndex == AppDestination.videos.index,
        selectedIndex: navigationShell.currentIndex,
        onSelect: (index) {
          if (index == navigationShell.currentIndex) return;
          navigationShell.goBranch(index);
        },
        content: navigationShell,
      ),
    );
  }
}
