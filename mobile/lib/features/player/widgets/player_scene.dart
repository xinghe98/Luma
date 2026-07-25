import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';
import '../player_interaction_controller.dart';
import 'player_controls.dart';
import 'player_feedback_hud.dart';
import 'player_gesture_layer.dart';
import 'player_video_surface.dart';

class PlayerScene extends StatelessWidget {
  /// 组合视频画面、手势反馈和全屏控制，并提供收起到小窗的入口。
  const PlayerScene({
    super.key,
    required this.controller,
    required this.interaction,
    required this.onBack,
    required this.onMinimize,
    required this.onRotate,
    this.attachVideo = true,
  });

  final PlayerController controller;
  final PlayerInteractionController interaction;
  final VoidCallback onBack;
  final VoidCallback onMinimize;
  final VoidCallback? onRotate;

  /// 为 false 时释放纹理给小窗，避免与 [MiniPlayerOverlay] 双挂载。
  final bool attachVideo;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: PlayerVideoSurface(
              controller: controller,
              attachVideo: attachVideo,
            ),
          ),
          PlayerGestureLayer(interaction: interaction),
          PlayerFeedbackHud(interaction: interaction),
          _PlayerDynamicOverlay(
            controller: controller,
            onBack: onBack,
            onMinimize: onMinimize,
            onRotate: onRotate,
          ),
        ],
      ),
    );
  }
}

class _PlayerDynamicOverlay extends StatelessWidget {
  const _PlayerDynamicOverlay({
    required this.controller,
    required this.onBack,
    required this.onMinimize,
    required this.onRotate,
  });

  final PlayerController controller;
  final VoidCallback onBack;
  final VoidCallback onMinimize;
  final VoidCallback? onRotate;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: _PlayerShade(visible: controller.controlsVisible),
          ),
          if (controller.error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(LumaSpacing.lg),
                child: Text(
                  controller.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: extras.onPlayerInkMuted),
                ),
              ),
            )
          else if (!controller.initialized || controller.buffering)
            IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(color: extras.onPlayerInk),
              ),
            ),
          AnimatedOpacity(
            opacity: controller.controlsVisible ? 1 : 0,
            duration: LumaMotion.forContext(context, LumaMotion.fast),
            curve: LumaMotion.standard,
            child: IgnorePointer(
              ignoring: !controller.controlsVisible,
              child: SafeArea(
                child: PlayerControls(
                  controller: controller,
                  onBack: onBack,
                  onMinimize: onMinimize,
                  onRotate: onRotate,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerShade extends StatelessWidget {
  const _PlayerShade({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final ink = context.luma.playerInk;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                ink.withAlpha(30),
                Colors.transparent,
                ink.withAlpha(50),
              ],
              stops: const [0, 0.48, 1],
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: LumaMotion.forContext(context, LumaMotion.normal),
          curve: LumaMotion.standard,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ink.withAlpha(130),
                  Colors.transparent,
                  ink.withAlpha(190),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
