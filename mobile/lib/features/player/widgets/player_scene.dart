import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme.dart';
import '../../../shared/media/media_artwork.dart';
import '../player_controller.dart';
import '../player_interaction_controller.dart';
import 'player_controls.dart';
import 'player_feedback_hud.dart';
import 'player_gesture_layer.dart';

class PlayerScene extends StatelessWidget {
  const PlayerScene({
    super.key,
    required this.controller,
    required this.interaction,
    required this.onBack,
    required this.onRotate,
  });

  final PlayerController controller;
  final PlayerInteractionController interaction;
  final VoidCallback onBack;
  final VoidCallback? onRotate;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: _PlayerVideoSurface(controller: controller)),
          PlayerGestureLayer(interaction: interaction),
          PlayerFeedbackHud(interaction: interaction),
          _PlayerDynamicOverlay(
            controller: controller,
            onBack: onBack,
            onRotate: onRotate,
          ),
        ],
      ),
    );
  }
}

class _PlayerVideoSurface extends StatefulWidget {
  const _PlayerVideoSurface({required this.controller});

  final PlayerController controller;

  @override
  State<_PlayerVideoSurface> createState() => _PlayerVideoSurfaceState();
}

class _PlayerVideoSurfaceState extends State<_PlayerVideoSurface> {
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PlayerVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_sync);
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final initialized = widget.controller.initialized;
    final error = widget.controller.error;
    if (_initialized == initialized && _error == error) return;
    if (mounted) {
      setState(() {
        _initialized = initialized;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.controller.videoController;
    if (_initialized && video != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: video.value.aspectRatio,
          child: VideoPlayer(video),
        ),
      );
    }
    return MediaArtwork(item: widget.controller.item, borderRadius: 0);
  }
}

class _PlayerDynamicOverlay extends StatelessWidget {
  const _PlayerDynamicOverlay({
    required this.controller,
    required this.onBack,
    required this.onRotate,
  });

  final PlayerController controller;
  final VoidCallback onBack;
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
