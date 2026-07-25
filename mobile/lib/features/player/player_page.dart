import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import 'player_controller.dart';
import 'player_device_controls.dart';
import 'player_interaction_controller.dart';
import 'player_session_controller.dart';
import 'player_system_ui.dart';
import 'widgets/player_scene.dart';

/// 播放指定媒体，并可选择忽略已保存的续播进度。
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.mediaId,
    this.startFromBeginning = false,
  });

  final String mediaId;
  final bool startFromBeginning;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  PlayerController? _controller;
  PlayerSessionController? _session;
  PlayerInteractionController? _interaction;
  final PlayerSystemUiSession _systemUi = PlayerSystemUiSession();
  bool _resolved = false;
  bool _minimizing = false;

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
    final session = AppScope.of(context).playerSession;
    final active = session.player;
    final item =
        media.findById(widget.mediaId) ??
        (active?.item.id == widget.mediaId ? active!.item : null);
    if (item == null) return;
    session.start(item, startFromBeginning: widget.startFromBeginning);
    final controller = session.player!;
    final interaction = PlayerInteractionController(
      player: controller,
      deviceControls: const MethodChannelPlayerDeviceControls(),
    );
    _controller = controller;
    _session = session;
    _interaction = interaction;
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
    // 收起过程中若页面被提前卸下（系统返回等），仍要进入小窗，避免无 UI 续播。
    if (_minimizing) {
      _session?.minimize();
    }
    final interaction = _interaction;
    _interaction = null;
    if (interaction != null) {
      unawaited(interaction.restoreDeviceState());
      interaction.dispose();
    }
    _controller = null;
    _session = null;
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
    final session = _session;
    return Scaffold(
      backgroundColor: extras.playerInk,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          controller,
          ?session,
        ]),
        builder: (context, _) {
          // 收起过程中先卸下全屏纹理，再交给小窗挂载，避免双绑定导致花屏/红屏。
          final attachVideo = !_minimizing && !(session?.minimized ?? false);
          return PopScope(
            canPop: !controller.locked,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop && !_minimizing) {
                unawaited(_session?.close());
              } else if (controller.locked) {
                controller.showLockHint();
              }
            },
            child: PlayerScene(
              controller: controller,
              interaction: interaction,
              attachVideo: attachVideo,
              onBack: _closeAndPop,
              onMinimize: _minimizeAndPop,
              onRotate: _systemUi.canRotate
                  ? () => unawaited(_systemUi.rotate())
                  : null,
            ),
          );
        },
      ),
    );
  }

  /// 收起页面时保留会话，由应用根层悬浮小窗继续展示。
  void _minimizeAndPop() {
    if (_minimizing) return;
    // 先卸全屏纹理，下一帧再让小窗接管并 pop。
    setState(() => _minimizing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session?.minimize();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    });
  }

  /// 正常返回会结束播放，避免未明确收起时继续占用解码器。
  void _closeAndPop() {
    unawaited(_session?.close());
    Navigator.of(context).pop();
  }
}
