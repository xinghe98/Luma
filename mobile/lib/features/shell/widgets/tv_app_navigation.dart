// TV 左侧常驻导航：五分支上下移动焦点、OK 切换分支、向右进入内容。
// 返回优先级：退出字段编辑 → 内容回导航 → 非首页回首页 → 首页退出系统；
// 弹层与根层详情页的返回由各自路由先行处理。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';
import '../../../shared/interaction/luma_focusable_surface.dart';
import '../../../shared/layout/tv_content_frame.dart';
import '../app_destination.dart';
import 'tv_field_gate.dart';

class TvAppNavigation extends StatefulWidget {
  const TvAppNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.content,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// 当前分支内容；未选分支由导航容器排除焦点，详情覆盖时保留来源焦点。
  final Widget content;

  @override
  State<TvAppNavigation> createState() => _TvAppNavigationState();
}

class _TvAppNavigationState extends State<TvAppNavigation> {
  final Map<int, FocusNode> _itemNodes = {
    for (final destination in AppDestination.values)
      destination.index: FocusNode(
        debugLabel: 'tv-nav-${destination.routeName}',
      ),
  };
  final _navScope = FocusScopeNode(debugLabel: 'tv-nav-scope');
  final _contentScope = FocusScopeNode(debugLabel: 'tv-content-scope');
  final Map<int, FocusNode> _branchFocus = {};
  bool _contentActive = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_rememberContentFocus);
  }

  // ExcludeFocus 会清除路由 scope 的历史；壳层只保存每个分支最后的实际控件。
  void _rememberContentFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (_contentActive &&
        primary != null &&
        primary is! FocusScopeNode &&
        primary.ancestors.contains(_contentScope)) {
      _branchFocus[widget.selectedIndex] = primary;
    }
  }

  void _returnToNavigation() {
    _rememberContentFocus();
    setState(() => _contentActive = false);
    _itemNodes[widget.selectedIndex]?.requestFocus();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_rememberContentFocus);
    for (final node in _itemNodes.values) {
      node.dispose();
    }
    _navScope.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  /// 系统返回经 PopScope，键盘返回经焦点事件；均按同一层级执行一次。
  void _handleBack() {
    if (TvTextFieldGate.exitFocusedEditing()) return;
    final primary = FocusManager.instance.primaryFocus;
    final inNav = primary == null || primary == _navScope || _navScope.hasFocus;
    if (!inNav) {
      _returnToNavigation();
      return;
    }
    if (widget.selectedIndex != AppDestination.home.index) {
      _selectBranch(AppDestination.home.index);
      return;
    }
    unawaited(SystemNavigator.pop());
  }

  /// 分支 Navigator 挂载后把焦点还给触发项，避免新路由抢走导航焦点。
  void _selectBranch(int index) {
    setState(() => _contentActive = false);
    widget.onSelect(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _itemNodes[index]?.requestFocus();
    });
  }

  /// 导航向右才开放内容焦点，分支挂载期间不会抢走当前导航项。
  KeyEventResult _handleNavigationKey(FocusNode node, KeyEvent event) {
    if (_handleBackKey(event) == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() => _contentActive = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_contentActive) return;
        final remembered = _branchFocus[widget.selectedIndex];
        if (remembered != null &&
            remembered.context != null &&
            remembered.canRequestFocus &&
            remembered.ancestors.contains(_contentScope)) {
          remembered.requestFocus();
        } else {
          // forward traversal 会继续进入嵌套 Navigator，scope.requestFocus 不会。
          _contentScope.nextFocus();
        }
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleBackKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape &&
        event.logicalKey != LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      final route = focusedContext == null
          ? null
          : ModalRoute.of(focusedContext);
      if (route != null && !route.isFirst) {
        unawaited(Navigator.of(focusedContext!).maybePop());
      } else {
        _handleBack();
      }
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _handleContentKey(FocusNode node, KeyEvent event) {
    if (_handleBackKey(event) == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final primary = FocusManager.instance.primaryFocus;
      final focusedContext = primary?.context;
      final route = focusedContext == null
          ? null
          : ModalRoute.of(focusedContext);
      if (route != null && !route.isFirst) return KeyEventResult.ignored;
      // 集合先处理内部移动；路由边界 stop 后才回导航，不跨过仍可达的控件。
      if (primary != null &&
          !primary.focusInDirection(TraversalDirection.left)) {
        _returnToNavigation();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FocusTraversalGroup(
              child: FocusScope(
                node: _navScope,
                onKeyEvent: _handleNavigationKey,
                onFocusChange: (focused) {
                  if (focused && _contentActive) {
                    setState(() => _contentActive = false);
                  }
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        MediaQuery.sizeOf(context).width <
                        LumaLayout.navigationRailBreakpoint;
                    return _TvNavigationRail(
                      selectedIndex: widget.selectedIndex,
                      onSelect: _selectBranch,
                      itemNodes: _itemNodes,
                      compact: compact,
                    );
                  },
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: FocusTraversalGroup(
                child: ExcludeFocus(
                  excluding: !_contentActive,
                  child: FocusScope(
                    node: _contentScope,
                    onKeyEvent: _handleContentKey,
                    child: TvContentFrame(child: widget.content),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvNavigationRail extends StatelessWidget {
  const _TvNavigationRail({
    required this.selectedIndex,
    required this.onSelect,
    required this.itemNodes,
    required this.compact,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Map<int, FocusNode> itemNodes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final railWidth = compact
        ? LumaTvLayout.navigationWidthCompact
        : LumaTvLayout.navigationWidth;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(
        width: railWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: LumaSpacing.lg,
                bottom: LumaSpacing.lg,
              ),
              child: Center(
                child: BrandMark(
                  variant: BrandMarkVariant.symbol,
                  compact: true,
                  height: compact ? 32 : 40,
                ),
              ),
            ),
            for (final destination in AppDestination.values)
              _TvNavigationItem(
                destination: destination,
                selected: destination.index == selectedIndex,
                compact: compact,
                focusNode: itemNodes[destination.index]!,
                autofocus: destination.index == selectedIndex,
                onSelect: onSelect,
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _TvNavigationItem extends StatelessWidget {
  const _TvNavigationItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.focusNode,
    required this.autofocus,
    required this.onSelect,
  });

  final AppDestination destination;
  final bool selected;
  final bool compact;
  final FocusNode focusNode;
  final bool autofocus;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LumaSpacing.sm,
        vertical: LumaSpacing.xxs,
      ),
      child: LumaFocusableSurface(
        label: destination.label,
        focusNode: focusNode,
        autofocus: autofocus,
        focusBorderWidth: LumaTvLayout.focusStroke,
        borderRadius: BorderRadius.circular(LumaRadii.medium),
        onActivate: () => onSelect(destination.index),
        child: AnimatedContainer(
          duration: LumaMotion.forContext(context, LumaMotion.fast),
          curve: Curves.easeOutQuart,
          height: compact ? LumaTvLayout.controlMinHeight : 72,
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(LumaRadii.medium),
          ),
          child: compact
              ? Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      color: selected
                          ? colors.onSecondaryContainer
                          : colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: LumaSpacing.xxs),
                    Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
