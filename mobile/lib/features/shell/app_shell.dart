import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../shared/interaction/tv_key_bindings.dart';
import 'app_destination.dart';
import 'widgets/adaptive_app_navigation.dart';
import 'search_return_scope.dart';

/// 壳层记录最近访问的主目的地分支；搜索是隐藏分支，关闭时回到该记录。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 进入隐藏分支（搜索）前最后所在的主目的地分支序号。
  int _lastPrimaryIndex = AppDestination.home.index;

  @override
  void initState() {
    super.initState();
    _rememberPrimary();
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberPrimary();
  }

  /// 当前分支是主目的地时记下它；深链直接进入某主分支时也能正确返回。
  void _rememberPrimary() {
    final index = widget.navigationShell.currentIndex;
    if (AppDestination.primaryIndexOf(index) != null) {
      _lastPrimaryIndex = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    // TV 差异只读注入的设备能力，不在此探测平台或屏幕尺寸。
    if (AppScope.of(context).deviceProfile.isTelevision) {
      return _TvShell(navigationShell: widget.navigationShell);
    }
    final navigationShell = widget.navigationShell;
    final currentIndex = navigationShell.currentIndex;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            navigationShell.goBranch(AppDestination.search.index),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            Navigator.of(context).maybePop(),
      },
      child: SearchReturnScope(
        close: () => navigationShell.goBranch(_lastPrimaryIndex),
        // 搜索分支自身导航栈只有一页，系统 Back 会落到根路由；在壳层拦截才能回到来源主目的地。
        child: PopScope(
          canPop: currentIndex != AppDestination.search.index,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && currentIndex == AppDestination.search.index) {
              navigationShell.goBranch(_lastPrimaryIndex);
            }
          },
          child: Focus(
            autofocus: true,
            child: AdaptiveAppNavigation(
              selectedIndex: currentIndex,
              onSelect: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == currentIndex,
              ),
              content: navigationShell,
            ),
          ),
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
