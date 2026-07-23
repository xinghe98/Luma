import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
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
    final extras = context.luma;
    if (controller == null || interaction == null) {
      return Scaffold(
        backgroundColor: extras.playerInk,
        appBar: AppBar(
          backgroundColor: extras.playerInk,
          foregroundColor: extras.onPlayerInk,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(LumaSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '找不到该媒体，可能已被移除或尚未加载。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: extras.onPlayerInkMuted),
                ),
                const SizedBox(height: LumaSpacing.md),
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
    return Scaffold(
      backgroundColor: extras.playerInk,
      body: ListenableBuilder(
        listenable: controller,
        child: _PlayerScene(
          controller: controller,
          interaction: interaction,
          onBack: () => Navigator.pop(context),
          onRotate: _systemUi.canRotate
              ? () => unawaited(_systemUi.rotate())
              : null,
        ),
        builder: (context, child) => PopScope(
          canPop: !controller.locked,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && controller.locked) controller.showLockHint();
          },
          child: child!,
        ),
      ),
    );
  }
}

/// Keeps the native video texture stable while position updates arrive several
/// times per second. Only initialization/error/buffering transitions rebuild
/// this subtree; controls still listen to the live player state separately.
class _PlayerScene extends StatelessWidget {
  const _PlayerScene({
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
    return Stack(
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
