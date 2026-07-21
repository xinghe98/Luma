import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_scope.dart';
import '../../shared/media/media_artwork.dart';
import 'player_controller.dart';
import 'player_device_controls.dart';
import 'player_interaction_controller.dart';
import 'player_system_ui.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_feedback_hud.dart';
import 'widgets/player_gesture_layer.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.mediaId});

  final String mediaId;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  PlayerController? _controller;
  PlayerInteractionController? _interaction;
  final PlayerSystemUiSession _systemUi = PlayerSystemUiSession();
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    final media = AppScope.of(context).media;
    final item = media.findById(widget.mediaId);
    if (item == null) return;
    final controller = PlayerController(
      item: item,
      media: media,
      apiSession: AppScope.of(context).apiSession,
    );
    final interaction = PlayerInteractionController(
      player: controller,
      deviceControls: const MethodChannelPlayerDeviceControls(),
    );
    _controller = controller;
    _interaction = interaction;
    controller.start();
    unawaited(interaction.initialize());
    final mediaQuery = MediaQuery.of(context);
    unawaited(
      _systemUi.enter(
        portraitVideo: item.isPortrait,
        entryOrientation: mediaQuery.orientation,
        shortestSide: mediaQuery.size.shortestSide,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final interaction = _interaction;
    _interaction = null;
    if (interaction != null) {
      unawaited(interaction.restoreDeviceState());
      interaction.dispose();
    }
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.shutdown());
    unawaited(_systemUi.exit());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_controller?.persistProgress());
      unawaited(_interaction?.restoreDeviceState());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_interaction?.initialize());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final interaction = _interaction;
    if (controller == null || interaction == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '找不到该媒体，可能已被移除或尚未加载。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopScope(
        canPop: !controller.locked,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && controller.locked) controller.showLockHint();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (controller.initialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.videoController!.value.aspectRatio,
                    child: VideoPlayer(controller.videoController!),
                  ),
                )
              else
                MediaArtwork(item: controller.item, borderRadius: 0),
              _PlayerShade(visible: controller.controlsVisible),
              PlayerGestureLayer(interaction: interaction),
              PlayerFeedbackHud(interaction: interaction),
              if (controller.error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      controller.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              else if (!controller.initialized || controller.buffering)
                const IgnorePointer(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              AnimatedOpacity(
                opacity: controller.controlsVisible ? 1 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutQuart,
                child: IgnorePointer(
                  ignoring: !controller.controlsVisible,
                  child: SafeArea(
                    child: PlayerControls(
                      controller: controller,
                      onBack: () => Navigator.pop(context),
                      onRotate: _systemUi.canRotate
                          ? () => unawaited(_systemUi.rotate())
                          : null,
                    ),
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

class _PlayerShade extends StatelessWidget {
  const _PlayerShade({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withAlpha(30),
              Colors.transparent,
              Colors.black.withAlpha(50),
            ],
            stops: const [0, 0.48, 1],
          ),
        ),
      ),
      AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withAlpha(130),
                Colors.transparent,
                Colors.black.withAlpha(190),
              ],
              stops: const [0, 0.48, 1],
            ),
          ),
        ),
      ),
    ],
  );
}
