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
    return Stack(
      fit: StackFit.expand,
      children: [
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final controlsVisible =
                controller.controlsVisible && controller.error == null;
            return Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(child: _PlayerShade(visible: controlsVisible)),
                AnimatedOpacity(
                  opacity: controlsVisible ? 1 : 0,
                  duration: LumaMotion.forContext(context, LumaMotion.fast),
                  curve: LumaMotion.standard,
                  child: IgnorePointer(
                    ignoring: !controlsVisible,
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
            );
          },
        ),
        _PlayerStatus(controller: controller),
      ],
    );
  }
}

// 只在加载、缓冲或错误状态变化时重建，播放进度不会反复创建状态提示。
class _PlayerStatus extends StatefulWidget {
  const _PlayerStatus({required this.controller});

  final PlayerController controller;

  @override
  State<_PlayerStatus> createState() => _PlayerStatusState();
}

class _PlayerStatusState extends State<_PlayerStatus> {
  late bool _initialized;
  late bool _buffering;
  String? _error;

  @override
  void initState() {
    super.initState();
    _readState();
    widget.controller.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant _PlayerStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_sync);
    _readState();
    widget.controller.addListener(_sync);
  }

  void _readState() {
    _initialized = widget.controller.initialized;
    _buffering = widget.controller.buffering;
    _error = widget.controller.error;
  }

  void _sync() {
    final initialized = widget.controller.initialized;
    final buffering = widget.controller.buffering;
    final error = widget.controller.error;
    if (initialized == _initialized &&
        buffering == _buffering &&
        error == _error) {
      return;
    }
    if (!mounted) return;
    setState(_readState);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(LumaSpacing.lg),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: extras.onPlayerInkMuted),
                ),
                const SizedBox(height: LumaSpacing.md),
                FilledButton.icon(
                  onPressed: widget.controller.retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试播放'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_initialized && !_buffering) return const SizedBox.shrink();
    return Semantics(
      label: _buffering ? '正在缓冲' : '正在准备播放',
      liveRegion: true,
      child: IgnorePointer(
        child: Center(
          child: CircularProgressIndicator(color: extras.onPlayerInk),
        ),
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
