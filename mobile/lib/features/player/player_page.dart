// PlayerPage coordinates media lookup, player lifecycle, device interaction, and system UI.
// It owns teardown ordering so leaving playback never leaves device or overlay state behind.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import 'player_controller.dart';
import 'player_device_controls.dart';
import 'player_interaction_controller.dart';
import 'player_system_ui.dart';
import 'widgets/player_scene.dart';

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
        child: PlayerScene(
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
