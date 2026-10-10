// 播放器底部工具栏：桌面端为静音与音量、移动端为锁定；
// 右侧按顺序提供字幕、音轨、倍速与旋转/全屏入口。
// 轨道选择复用 showSingleChoiceSheet，打开期间暂停控制层自动隐藏。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/single_choice_sheet.dart';
import '../player_controller.dart';
import '../player_track_labels.dart';
import 'player_control_button.dart';
import 'tv_player_controls.dart' show kTvPlaybackSpeeds;

/// 桌面端音量滑块的固定宽度。
const double _volumeSliderWidth = 132;

class PlayerBottomToolbar extends StatelessWidget {
  /// 构建平台化底栏；桌面显示音量和全屏，移动端保留锁定与旋转。
  const PlayerBottomToolbar({
    super.key,
    required this.controller,
    required this.onRotate,
    this.isDesktop = false,
    this.isFullScreen = false,
    this.onToggleFullScreen,
  });

  final PlayerController controller;
  final VoidCallback? onRotate;
  final bool isDesktop;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isDesktop) ...[
          PlayerControlButton(
            icon: controller.muted || controller.volume <= 0
                ? Icons.volume_off_rounded
                : controller.volume < 0.5
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
            tooltip: controller.muted ? '取消静音' : '静音',
            onPressed: controller.toggleMute,
          ),
          SizedBox(
            width: _volumeSliderWidth,
            child: Slider(
              value: controller.volume,
              onChanged: controller.setLocalVolume,
              semanticFormatterCallback: (value) =>
                  '音量 ${(value * 100).round()}%',
            ),
          ),
        ] else
          PlayerControlButton(
            icon: Icons.lock_open_rounded,
            tooltip: '锁定控制',
            onPressed: () => controller.setLocked(true),
          ),
        const Spacer(),
        if (controller.subtitleTracks.isNotEmpty)
          PlayerControlButton(
            icon: Icons.subtitles_rounded,
            tooltip: '字幕',
            onPressed: () => unawaited(_chooseSubtitle(context)),
          ),
        if (controller.audioTracks.length > 1)
          PlayerControlButton(
            icon: Icons.audiotrack_rounded,
            tooltip: '音轨',
            onPressed: () => unawaited(_chooseAudio(context)),
          ),
        _PlaybackSpeedMenu(controller: controller),
        if (isDesktop)
          PlayerControlButton(
            icon: isFullScreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            tooltip: isFullScreen ? '退出全屏' : '进入全屏',
            onPressed: onToggleFullScreen,
          )
        else
          PlayerControlButton(
            icon: Icons.screen_rotation_alt_rounded,
            tooltip: '旋转屏幕',
            onPressed: onRotate,
          ),
      ],
    );
  }

  /// 弹出字幕轨选择；关闭后恢复控制层自动隐藏计时。
  Future<void> _chooseSubtitle(BuildContext context) async {
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
    if (selected != null) controller.selectSubtitleTrack(selected);
    controller.scheduleHide();
  }

  /// 弹出音轨选择；关闭后恢复控制层自动隐藏计时。
  Future<void> _chooseAudio(BuildContext context) async {
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
    if (selected != null) controller.selectAudioTrack(selected);
    controller.scheduleHide();
  }
}

/// 倍速入口：图标加当前倍速标签，弹出档位菜单。
class _PlaybackSpeedMenu extends StatelessWidget {
  const _PlaybackSpeedMenu({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    final speed = controller.speed;
    final speedLabel = speed == 1 ? '1.0×' : '$speed×';
    return PopupMenuButton<double>(
      tooltip: '播放速度',
      initialValue: speed,
      onSelected: controller.setSpeed,
      itemBuilder: (_) => kTvPlaybackSpeeds
          .map((value) => PopupMenuItem(value: value, child: Text('$value×')))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LumaSpacing.sm,
          vertical: LumaSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed_rounded, size: 20, color: extras.onPlayerInk),
            const SizedBox(width: LumaSpacing.xxs),
            Text(
              speedLabel,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: extras.onPlayerInk),
            ),
          ],
        ),
      ),
    );
  }
}
