// 手机底栏与宽屏侧栏共用的导航项、滑动胶囊和延迟选中逻辑。
// 胶囊几何由外层栏计算并传入，导航项只负责同一位置的悬停、按压、焦点反馈。
// 选中态先提交目标分支首帧，再在下一帧启动胶囊滑动，避免两者争抢同一帧。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../app_destination.dart';

/// 导航项内容排布：底栏与收起侧栏为图标在上，展开侧栏为图标与文字同行。
enum NavigationItemLayout { stacked, inline }

/// 延迟同步视觉选中项：路由先切换分支，下一帧再移动胶囊和切换图标。
///
/// 使用方实现 [selectedBranch]，读取 [visualBranch] 绘制选中态；连续快速切换时
/// 只保留最后一次目标，过期回调会被丢弃。
mixin DeferredNavigationSelection<T extends StatefulWidget> on State<T> {
  /// 路由当前分支序号，即语义上的选中项。
  int get selectedBranch;

  /// 当前用于绘制的分支序号，可能比 [selectedBranch] 晚一帧。
  late int visualBranch;
  int? _scheduledBranch;

  @override
  void initState() {
    super.initState();
    visualBranch = selectedBranch;
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selectedBranch != visualBranch && selectedBranch != _scheduledBranch) {
      _scheduleVisualBranch(selectedBranch);
    }
  }

  void _scheduleVisualBranch(int branch) {
    _scheduledBranch = branch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scheduledBranch != branch) return;
      _scheduledBranch = null;
      if (selectedBranch != branch) {
        if (selectedBranch != visualBranch) {
          _scheduleVisualBranch(selectedBranch);
        }
        return;
      }
      setState(() => visualBranch = branch);
    });
  }
}

/// 按槽位进度 [t] 在相邻胶囊矩形之间分段插值，跨多个槽位时依次经过中间项。
///
/// 进度来自选中动画，矩形来自当前布局；窗口缩放时胶囊立即贴合新布局。
Rect lerpNavigationSlots(List<Rect> rects, double t) {
  final clamped = t.clamp(0.0, rects.length - 1.0);
  final lower = clamped.floor();
  final upper = clamped.ceil();
  return Rect.lerp(rects[lower], rects[upper], clamped - lower)!;
}

/// 选中项背后的主色淡胶囊；位置与动画由外层栏控制。
class NavigationCapsule extends StatelessWidget {
  const NavigationCapsule({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: LumaOpacity.selected),
          borderRadius: BorderRadius.circular(LumaRadii.badge),
        ),
      ),
    );
  }
}

/// 单个导航项：整块区域可点击，反馈只画在 [capsule] 所在的胶囊里。
///
/// [capsule] 是相对导航项左上角的矩形，必须与外层滑动胶囊的落点一致。
/// 支持触控、鼠标悬停、键盘焦点与 Enter/Space 激活；不产生水波纹。
class NavigationItem extends StatefulWidget {
  const NavigationItem({
    super.key,
    required this.destination,
    required this.layout,
    required this.capsule,
    required this.selected,
    required this.semanticallySelected,
    required this.onTap,
    this.semanticsKey,
  });

  final AppDestination destination;
  final NavigationItemLayout layout;
  final Rect capsule;

  /// 视觉选中：决定图标、颜色与字重，可能比语义选中晚一帧。
  final bool selected;

  /// 语义选中：读屏与测试依据，随路由立即更新。
  final bool semanticallySelected;
  final VoidCallback onTap;

  /// 挂在语义节点上的 key，供壳层测试定位导航项。
  final Key? semanticsKey;

  @override
  State<NavigationItem> createState() => _NavigationItemState();
}

class _NavigationItemState extends State<NavigationItem> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final destination = widget.destination;
    final selected = widget.selected;
    final contentColor = selected ? colors.primary : colors.onSurfaceVariant;
    final overlayOpacity = _pressed
        ? LumaOpacity.pressed
        : _hovered
        ? LumaOpacity.hover
        : 0.0;
    // 只有键盘导航时才画焦点描边，触控点击不留残影。
    final showFocusRing =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final baseStyle = widget.layout == NavigationItemLayout.stacked
        ? theme.textTheme.labelMedium
        : theme.textTheme.labelLarge;
    final labelStyle = baseStyle?.copyWith(
      color: contentColor,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      height: 1.3,
    );
    final icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      color: contentColor,
      size: LumaIconSize.action,
    );
    final label = Text(
      destination.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: labelStyle,
    );
    final capsule = widget.capsule;

    return Semantics(
      key: widget.semanticsKey,
      button: true,
      selected: widget.semanticallySelected,
      label: destination.label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hovered = value),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          onFocusChange: (value) => setState(() => _focused = value),
          mouseCursor: SystemMouseCursors.click,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: capsule,
                child: AnimatedContainer(
                  duration: LumaMotion.forContext(context, LumaMotion.fast),
                  curve: LumaMotion.standard,
                  decoration: ShapeDecoration(
                    color: contentColor.withValues(alpha: overlayOpacity),
                    shape: StadiumBorder(
                      side: showFocusRing
                          ? BorderSide(color: colors.primary, width: 2)
                          : BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (widget.layout == NavigationItemLayout.stacked) ...[
                Positioned.fromRect(
                  rect: capsule,
                  child: Center(child: icon),
                ),
                Positioned(
                  left: LumaSpacing.xxs,
                  right: LumaSpacing.xxs,
                  top: capsule.bottom + LumaSpacing.xxs,
                  child: Center(child: label),
                ),
              ] else
                Positioned.fromRect(
                  rect: capsule,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LumaSpacing.md,
                    ),
                    child: Row(
                      children: [
                        icon,
                        const SizedBox(width: LumaSpacing.sm),
                        Expanded(child: label),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
