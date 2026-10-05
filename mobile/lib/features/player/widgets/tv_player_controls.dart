// TV 播放控制层：只提供遥控可操作的核心动作——播放/暂停、后退/前进 10 秒、
// 播放速度与关闭；不包含锁定、旋转、亮度、软件音量与小窗。
// 所有控件走 LumaFocusableSurface，焦点描边与最小高度使用 TV 布局常量；
// 控制层从隐藏变为可见时，把焦点交给播放按钮，速度弹窗关闭后焦点自动
// 由路由焦点作用域还给速度按钮。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../shared/interaction/luma_focusable_surface.dart';
import '../../../shared/widgets/single_choice_sheet.dart';
import '../player_controller.dart';
import 'player_timeline.dart';

/// TV 播放速度档位，与普通端底部工具栏保持一致。
const List<double> kTvPlaybackSpeeds = [0.5, 1.0, 1.25, 1.5, 2.0];

/// TV 全屏播放器的控制层；由 [PlayerScene] 在 television 分支挂载。
class TvPlayerControls extends StatefulWidget {
  /// 创建 TV 控制层；[onClose] 由播放器页面提供，负责结束会话并返回来源。
  const TvPlayerControls({
    super.key,
    required this.controller,
    required this.onClose,
    this.onSpeedDialogChanged,
  });

  final PlayerController controller;
  final VoidCallback onClose;

  /// 通知所属场景速度弹窗是否打开；打开时场景不得因起播重启隐藏计时。
  /// 关闭通知仅在控制层仍挂载时发出，焦点由弹窗路由恢复。
  final ValueChanged<bool>? onSpeedDialogChanged;

  @override
  State<TvPlayerControls> createState() => _TvPlayerControlsState();
}

class _TvPlayerControlsState extends State<TvPlayerControls> {
  final FocusNode _playNode = FocusNode();
  final FocusNode _timelineNode = FocusNode();
  final FocusNode _speedNode = FocusNode();
  final FocusNode _closeNode = FocusNode();
  bool _wasVisible = false;

  @override
  void initState() {
    super.initState();
    _wasVisible = widget.controller.controlsVisible;
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant TvPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChange);
    _wasVisible = widget.controller.controlsVisible;
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _playNode.dispose();
    _timelineNode.dispose();
    _speedNode.dispose();
    _closeNode.dispose();
    super.dispose();
  }

  /// 控制层从隐藏变为可见时，下一帧把焦点交给播放按钮；
  /// 隐藏侧的焦点交还输入根由播放器输入层负责。
  void _handleControllerChange() {
    final visible = widget.controller.controlsVisible;
    if (visible == _wasVisible) return;
    _wasVisible = visible;
    if (!visible || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.controlsVisible) return;
      _playNode.requestFocus();
    });
  }

  /// 打开速度选择期间暂停自动隐藏，关闭后仅在正常播放时恢复计时。
  /// 取消与选择都保留暂停状态的控制层，焦点由路由还给速度按钮。
  Future<void> _chooseSpeed() async {
    final controller = widget.controller;
    widget.onSpeedDialogChanged?.call(true);
    controller.pauseAutoHide();
    final selected = await showSingleChoiceSheet<double>(
      context,
      title: '播放速度',
      supportingText: '选择适合观看的播放速度',
      selectedValue: controller.speed,
      choices: kTvPlaybackSpeeds
          .map(
            (speed) => BottomSheetChoice<double>(
              value: speed,
              label: '${speed}x',
              icon: Icons.speed_rounded,
            ),
          )
          .toList(),
    );
    if (!mounted) return;
    widget.onSpeedDialogChanged?.call(false);
    if (selected != null) {
      // setSpeed 内部会重新显示控制层并重启自动隐藏计时。
      controller.setSpeed(selected);
    }
    if (controller.playing && controller.error == null) {
      controller.scheduleHide();
    } else {
      controller.pauseAutoHide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    final controller = widget.controller;
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(color: extras.onPlayerInk);
    final subtitleStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: extras.onPlayerInk.withValues(alpha: 0.72),
    );
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final viewport = MediaQuery.sizeOf(context);
        // 控制层独享四边 5% 安全边距；视频画面保持全屏。
        final safePadding = EdgeInsets.symmetric(
          horizontal: viewport.width * LumaTvLayout.safeAreaRatio,
          vertical: viewport.height * LumaTvLayout.safeAreaRatio,
        );
        return Padding(
          padding: safePadding,
          child: FocusTraversalGroup(
            // 拉伸使进度条占满整行，速度按钮可靠左对齐。
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _TvControl(
                      key: const ValueKey('tv-player-close'),
                      label: '关闭播放器',
                      icon: Icons.close_rounded,
                      onActivate: widget.onClose,
                      focusNode: _closeNode,
                    ),
                    const SizedBox(width: LumaSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            controller.item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          ),
                          if (controller.item.resolution.isNotEmpty)
                            Text(
                              controller.item.resolution,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtitleStyle,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TvControl(
                      label: '后退 10 秒',
                      icon: Icons.replay_10_rounded,
                      onActivate: () => controller.seekBy(-10),
                    ),
                    const SizedBox(width: LumaSpacing.lg),
                    _TvControl(
                      key: const ValueKey('tv-player-play'),
                      label: controller.playing ? '暂停' : '播放',
                      icon: controller.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onActivate: controller.togglePlay,
                      focusNode: _playNode,
                      autofocus: true,
                    ),
                    const SizedBox(width: LumaSpacing.lg),
                    _TvControl(
                      label: '快进 10 秒',
                      icon: Icons.forward_10_rounded,
                      onActivate: () => controller.seekBy(10),
                    ),
                  ],
                ),
                const Spacer(),
                // 进度条：外层表面获得焦点，左右键按 ±10 秒定位（非百分比步长），
                // 确认键切换播放；内部 Slider 不参与焦点，避免其默认键盘步长。
                Shortcuts(
                  shortcuts: {
                    SingleActivator(LogicalKeyboardKey.arrowLeft):
                        VoidCallbackIntent(() => controller.seekBy(-10)),
                    SingleActivator(LogicalKeyboardKey.arrowRight):
                        VoidCallbackIntent(() => controller.seekBy(10)),
                  },
                  child: LumaFocusableSurface(
                    key: const ValueKey('tv-player-timeline'),
                    label: '播放进度：左右键快退快进 10 秒，确认键播放或暂停',
                    onActivate: controller.togglePlay,
                    focusNode: _timelineNode,
                    focusBorderWidth: LumaTvLayout.focusStroke,
                    borderRadius: BorderRadius.circular(LumaRadii.small),
                    child: ExcludeFocus(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: LumaSpacing.xs,
                        ),
                        child: PlayerTimeline(controller: controller),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: LumaSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _TvControl(
                    key: const ValueKey('tv-player-speed'),
                    label: '播放速度',
                    icon: Icons.speed_rounded,
                    trailing: '${controller.speed}x',
                    onActivate: _chooseSpeed,
                    focusNode: _speedNode,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// TV 控制层的单个动作：固定最小高度的图标按钮，聚焦时显示 3dp 描边。
class _TvControl extends StatelessWidget {
  const _TvControl({
    super.key,
    required this.label,
    required this.icon,
    required this.onActivate,
    this.trailing,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onActivate;

  /// 可选的文字后缀（如当前速度）；参与语义但整块仍是一个动作。
  final String? trailing;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: extras.onPlayerInk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LumaFocusableSurface(
      label: label,
      onActivate: onActivate,
      focusNode: focusNode,
      autofocus: autofocus,
      focusBorderWidth: LumaTvLayout.focusStroke,
      borderRadius: BorderRadius.circular(LumaRadii.small),
      child: Container(
        height: LumaTvLayout.controlMinHeight,
        padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: extras.onPlayerInk, size: LumaIconSize.prominent),
            if (trailing != null) ...[
              const SizedBox(width: LumaSpacing.xs),
              Text(trailing!, style: textStyle),
            ],
          ],
        ),
      ),
    );
  }
}
