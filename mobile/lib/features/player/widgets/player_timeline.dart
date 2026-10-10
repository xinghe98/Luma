import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../player_controller.dart';

class PlayerTimeline extends StatelessWidget {
  /// 播放进度时间轴；滑块下方叠加一条已缓冲进度条。
  const PlayerTimeline({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final onInk = context.luma.onPlayerInk;
    // 播放器背景恒定深色，轨道色不跟随亮/暗主题。
    const timelineColor = LumaColors.darkPrimary;
    final durationMs = controller.duration.inMilliseconds.toDouble();
    final positionMs = controller.position.inMilliseconds.clamp(
      0,
      controller.duration.inMilliseconds,
    );
    final buffered = controller.buffered;
    final bufferFraction = durationMs <= 0
        ? 0.0
        : (buffered.inMilliseconds / durationMs).clamp(0.0, 1.0);
    final timeStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: onInk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Text(formatClock(controller.position), style: timeStyle),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (bufferFraction > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LinearProgressIndicator(
                    value: bufferFraction,
                    minHeight: 4,
                    color: onInk.withValues(alpha: 0.38),
                    backgroundColor: onInk.withValues(alpha: 0.16),
                  ),
                ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: timelineColor,
                  inactiveTrackColor: onInk.withValues(alpha: 0.28),
                  thumbColor: timelineColor,
                  overlayColor: timelineColor.withValues(alpha: 0.16),
                ),
                child: Slider(
                  value: durationMs <= 0 ? 0 : positionMs.toDouble(),
                  max: durationMs <= 0 ? 1 : durationMs,
                  semanticFormatterCallback: durationMs <= 0
                      ? null
                      : (value) =>
                            '${formatClock(Duration(milliseconds: value.round()))}'
                            ' / ${formatClock(controller.duration)}',
                  onChangeStart: (_) => controller.beginScrub(),
                  onChanged: (value) => controller.updateScrub(
                    Duration(milliseconds: value.round()),
                  ),
                  onChangeEnd: (_) => controller.commitScrub(),
                ),
              ),
            ],
          ),
        ),
        Text(formatClock(controller.duration), style: timeStyle),
      ],
    );
  }
}
