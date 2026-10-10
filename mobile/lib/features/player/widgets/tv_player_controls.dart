// TV 播放控制层：只提供遥控可操作的核心动作——播放/暂停、后退/前进 10 秒、
// 选集、清晰度、字幕、音轨、速度与关闭；不包含锁定、旋转、亮度、软件音量与小窗。
// 控件走 LumaFocusableSurface。获焦时底板和图标对调，不靠一条近色描边辨认；
// 控制层从隐藏变为可见时，把焦点交给播放按钮，速度弹窗关闭后焦点自动
// 由路由焦点作用域还给速度按钮。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme.dart';
import '../../../shared/interaction/luma_focusable_surface.dart';
import '../../../shared/widgets/single_choice_sheet.dart';
import '../player_controller.dart';
import '../player_selection_controller.dart';
import '../player_track_labels.dart';
import 'player_ended_overlay.dart';
import 'player_selection_sheet.dart';
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
    this.selection,
    this.onSpeedDialogChanged,
  });

  final PlayerController controller;
  final VoidCallback onClose;

  /// 剧集/清晰度选择控制器；为 null 时隐藏相关入口。
  final PlayerSelectionController? selection;

  /// 通知所属场景选择/速度弹窗是否打开；打开时场景不得因起播重启隐藏计时。
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

  /// 弹出字幕轨选择；关闭后恢复自动隐藏计时。轨目变化时列表实时刷新。
  Future<void> _chooseSubtitle() async {
    final controller = widget.controller;
    widget.onSpeedDialogChanged?.call(true);
    controller.pauseAutoHide();
    final tracks = controller.subtitleTracks;
    final offTrack = SubtitleTrack.no();
    final selected = await showSingleChoiceSheet<SubtitleTrack>(
      context,
      title: '字幕',
      supportingText: '选择字幕轨道',
      selectedValue: controller.selectedSubtitle,
      choices: [
        BottomSheetChoice<SubtitleTrack>(
          value: offTrack,
          label: '关闭',
          icon: Icons.subtitles_off_rounded,
        ),
        for (var i = 0; i < tracks.length; i++)
          BottomSheetChoice<SubtitleTrack>(
            value: tracks[i],
            label: trackLabel(
              title: tracks[i].title,
              language: tracks[i].language,
              index: i,
              fallbackPrefix: '字幕',
            ),
            icon: Icons.subtitles_rounded,
          ),
      ],
    );
    if (!mounted) return;
    widget.onSpeedDialogChanged?.call(false);
    if (selected != null) controller.selectSubtitleTrack(selected);
    if (controller.playing && controller.error == null) {
      controller.scheduleHide();
    } else {
      controller.pauseAutoHide();
    }
  }

  /// 弹出音轨选择；关闭后恢复自动隐藏计时。
  Future<void> _chooseAudio() async {
    final controller = widget.controller;
    widget.onSpeedDialogChanged?.call(true);
    controller.pauseAutoHide();
    final tracks = controller.audioTracks;
    final selected = await showSingleChoiceSheet<AudioTrack>(
      context,
      title: '音轨',
      supportingText: '选择音频轨道',
      selectedValue: controller.selectedAudio,
      choices: [
        for (var i = 0; i < tracks.length; i++)
          BottomSheetChoice<AudioTrack>(
            value: tracks[i],
            label: trackLabel(
              title: tracks[i].title,
              language: tracks[i].language,
              index: i,
              fallbackPrefix: '音轨',
            ),
            icon: Icons.audiotrack_rounded,
          ),
      ],
    );
    if (!mounted) return;
    widget.onSpeedDialogChanged?.call(false);
    if (selected != null) controller.selectAudioTrack(selected);
    if (controller.playing && controller.error == null) {
      controller.scheduleHide();
    } else {
      controller.pauseAutoHide();
    }
  }

  /// 弹出选集/清晰度面板；模态生命周期与速度弹窗一致，
  /// 关闭后焦点由路由还给入口按钮，播放状态决定恢复或继续暂停计时。
  Future<void> _chooseSelection(PlayerSelectionKind kind) async {
    final controller = widget.controller;
    final selection = widget.selection;
    if (selection == null) return;
    widget.onSpeedDialogChanged?.call(true);
    controller.pauseAutoHide();
    await showPlayerSelectionSheet(context, controller: selection, kind: kind);
    if (!mounted) return;
    widget.onSpeedDialogChanged?.call(false);
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
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LumaGradients.bottomScrim(extras.playerInk),
          ),
          child: Padding(
            padding: safePadding,
            child: FocusTraversalGroup(
              child: Column(
                key: const ValueKey('tv-player-bottom-controls'),
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    controller.item.title,
                    key: const ValueKey('tv-player-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (controller.item.resolution.isNotEmpty)
                    Text(controller.item.resolution, style: subtitleStyle),
                  const SizedBox(height: LumaSpacing.md),
                  // 时间轴独立一行；左右键仍按十秒步长定位，确认键播放或暂停。
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
                  const SizedBox(height: LumaSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final transport = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TvControl(
                            key: const ValueKey('tv-player-rewind'),
                            label: '后退 10 秒',
                            icon: Icons.replay_10_rounded,
                            onActivate: () => controller.seekBy(-10),
                          ),
                          const SizedBox(width: LumaSpacing.sm),
                          _TvControl(
                            key: const ValueKey('tv-player-play'),
                            label: controller.playing ? '暂停' : '播放',
                            icon: controller.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onActivate: controller.togglePlay,
                            focusNode: _playNode,
                            autofocus: true,
                            primary: true,
                          ),
                          const SizedBox(width: LumaSpacing.sm),
                          _TvControl(
                            key: const ValueKey('tv-player-forward'),
                            label: '快进 10 秒',
                            icon: Icons.forward_10_rounded,
                            onActivate: () => controller.seekBy(10),
                          ),
                        ],
                      );
                      final selection = widget.selection;
                      final secondary = ListenableBuilder(
                        listenable: selection ?? controller,
                        builder: (context, _) => Wrap(
                          spacing: LumaSpacing.sm,
                          runSpacing: LumaSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (selection != null) ...[
                              // 电影与独立视频不显示选集入口。
                              if (selection.showEpisodes) ...[
                                _TvControl(
                                  key: const ValueKey('player-episodes-button'),
                                  label: '选集',
                                  icon: Icons.video_library_rounded,
                                  onActivate: () => unawaited(
                                    _chooseSelection(
                                      PlayerSelectionKind.episodes,
                                    ),
                                  ),
                                ),
                              ],
                              _TvControl(
                                key: const ValueKey('player-quality-button'),
                                label: '清晰度',
                                icon: Icons.high_quality_rounded,
                                onActivate: () => unawaited(
                                  _chooseSelection(
                                    PlayerSelectionKind.qualities,
                                  ),
                                ),
                              ),
                            ],
                            if (controller.subtitleTracks.isNotEmpty) ...[
                              _TvControl(
                                key: const ValueKey('tv-player-subtitle'),
                                label: '字幕',
                                icon: Icons.subtitles_rounded,
                                onActivate: _chooseSubtitle,
                              ),
                            ],
                            if (controller.audioTracks.length > 1) ...[
                              _TvControl(
                                key: const ValueKey('tv-player-audio'),
                                label: '音轨',
                                icon: Icons.audiotrack_rounded,
                                onActivate: _chooseAudio,
                              ),
                            ],
                            _TvControl(
                              key: const ValueKey('tv-player-speed'),
                              label: '播放速度',
                              icon: Icons.speed_rounded,
                              trailing: '${controller.speed}x',
                              onActivate: _chooseSpeed,
                              focusNode: _speedNode,
                            ),
                            _TvControl(
                              key: const ValueKey('tv-player-close'),
                              label: '关闭播放器',
                              icon: Icons.close_rounded,
                              onActivate: widget.onClose,
                              focusNode: _closeNode,
                            ),
                          ],
                        ),
                      );
                      // 播完时用结束态替换运输行，返回交给页面路由处理。
                      if (controller.completed) {
                        return PlayerEndedOverlay(
                          key: const ValueKey('tv-player-transport'),
                          controller: controller,
                          television: true,
                          onExit: () =>
                              unawaited(Navigator.of(context).maybePop()),
                        );
                      }
                      // 窄电视窗口为次要操作另起一行，主运输区仍保持左右顺序。
                      if (constraints.maxWidth <
                          LumaLayout.navigationRailBreakpoint) {
                        return Column(
                          key: const ValueKey('tv-player-transport'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            transport,
                            const SizedBox(height: LumaSpacing.sm),
                            secondary,
                          ],
                        );
                      }
                      return Row(
                        key: const ValueKey('tv-player-transport'),
                        children: [
                          transport,
                          const SizedBox(width: LumaSpacing.lg),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: secondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// TV 控制层的单个动作：固定最小高度，获焦时底板和图标对调。
class _TvControl extends StatelessWidget {
  const _TvControl({
    super.key,
    required this.label,
    required this.icon,
    required this.onActivate,
    this.trailing,
    this.focusNode,
    this.autofocus = false,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onActivate;

  /// 可选的文字后缀（如当前速度）；参与语义但整块仍是一个动作。
  final String? trailing;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    return LumaFocusableSurface(
      label: label,
      onActivate: onActivate,
      focusNode: focusNode,
      autofocus: autofocus,
      focusBorderWidth: LumaTvLayout.focusStroke,
      borderRadius: BorderRadius.circular(LumaRadii.small),
      child: Builder(
        builder: (context) {
          final focused = LumaFocusMark.focusedOf(context);
          final foreground = focused ? extras.playerInk : extras.onPlayerInk;
          final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
            color: foreground,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          return Container(
            height: LumaTvLayout.controlMinHeight,
            padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
            decoration: BoxDecoration(
              color: focused
                  ? extras.onPlayerInk
                  : primary
                  ? extras.onPlayerInk.withValues(alpha: 0.18)
                  : null,
              borderRadius: BorderRadius.circular(LumaRadii.small),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: LumaIconSize.prominent),
                if (trailing != null) ...[
                  const SizedBox(width: LumaSpacing.xs),
                  Text(trailing!, style: textStyle),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
