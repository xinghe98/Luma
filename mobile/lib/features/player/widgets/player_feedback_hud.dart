import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../player_interaction_controller.dart';

class PlayerFeedbackHud extends StatefulWidget {
  const PlayerFeedbackHud({super.key, required this.interaction});

  final PlayerInteractionController interaction;

  @override
  State<PlayerFeedbackHud> createState() => _PlayerFeedbackHudState();
}

class _PlayerFeedbackHudState extends State<PlayerFeedbackHud> {
  /// 淡出时保留最后一帧内容，避免 hidden 占位图标闪一下。
  _HudPresentation _lastPresentation = const _HudPresentation(
    icon: Icons.fast_forward_rounded,
    title: '',
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.interaction,
      builder: (context, _) {
        final presentation = _presentation();
        if (widget.interaction.hudVisible) {
          _lastPresentation = presentation;
        }
        final shown = widget.interaction.hudVisible
            ? presentation
            : _lastPresentation;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final extras = context.luma;
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: widget.interaction.hudVisible ? 1 : 0,
            duration: reduceMotion ? Duration.zero : LumaMotion.fast,
            curve: LumaMotion.standard,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: extras.playerInk.withAlpha(235),
                    borderRadius: BorderRadius.circular(LumaRadii.medium),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LumaSpacing.md,
                      vertical: LumaSpacing.sm,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(shown.icon, color: extras.onPlayerInk, size: 28),
                        const SizedBox(height: LumaSpacing.xs),
                        Text(
                          shown.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: extras.onPlayerInk),
                        ),
                        if (shown.subtitle != null) ...[
                          const SizedBox(height: LumaSpacing.xxs),
                          Text(
                            shown.subtitle!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: extras.onPlayerInkMuted),
                          ),
                        ],
                        if (shown.progress != null) ...[
                          const SizedBox(height: LumaSpacing.sm),
                          SizedBox(
                            width: 210,
                            child: LinearProgressIndicator(
                              value: shown.progress!.clamp(0, 1),
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(
                                LumaRadii.badge,
                              ),
                              backgroundColor: extras.onPlayerInk.withValues(
                                alpha: 0.24,
                              ),
                              color: LumaColors.gold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  _HudPresentation _presentation() {
    final interaction = widget.interaction;
    switch (interaction.hudKind) {
      case PlayerHudKind.seek:
        final deltaSeconds = interaction.seekDelta.inSeconds;
        final sign = deltaSeconds > 0 ? '+' : '';
        return _HudPresentation(
          icon: deltaSeconds < 0
              ? Icons.fast_rewind_rounded
              : Icons.fast_forward_rounded,
          title:
              '${formatDuration(interaction.seekTarget)} / '
              '${formatDuration(interaction.player.duration)}',
          subtitle: '$sign$deltaSeconds 秒',
          progress: interaction.seekProgress,
        );
      case PlayerHudKind.brightness:
        return _HudPresentation(
          icon: Icons.brightness_6_rounded,
          title: '亮度 ${(interaction.brightness * 100).round()}%',
          progress: interaction.brightness,
        );
      case PlayerHudKind.volume:
        return _HudPresentation(
          icon: interaction.volume == 0
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          title: '音量 ${(interaction.volume * 100).round()}%',
          progress: interaction.volume,
        );
      case PlayerHudKind.backward:
        return const _HudPresentation(
          icon: Icons.replay_10_rounded,
          title: '后退 10 秒',
        );
      case PlayerHudKind.forward:
        return const _HudPresentation(
          icon: Icons.forward_10_rounded,
          title: '快进 10 秒',
        );
      case PlayerHudKind.play:
        return const _HudPresentation(
          icon: Icons.play_arrow_rounded,
          title: '继续播放',
        );
      case PlayerHudKind.pause:
        return const _HudPresentation(icon: Icons.pause_rounded, title: '已暂停');
      case PlayerHudKind.speed:
        return const _HudPresentation(
          icon: Icons.fast_forward_rounded,
          title: '2.0x 快速播放',
          subtitle: '松手恢复原速度',
        );
      case PlayerHudKind.hidden:
        return _lastPresentation;
    }
  }
}

class _HudPresentation {
  const _HudPresentation({
    required this.icon,
    required this.title,
    this.subtitle,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final double? progress;
}
