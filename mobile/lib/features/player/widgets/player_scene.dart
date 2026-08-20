import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';
import '../player_interaction_controller.dart';
import 'player_controls.dart';
import 'player_feedback_hud.dart';
import 'player_gesture_layer.dart';
import 'player_video_surface.dart';

class PlayerScene extends StatelessWidget {
  /// 组合视频、反馈和控制；桌面端额外提供键盘、鼠标与窗口全屏。
  const PlayerScene({
    super.key,
    required this.controller,
    required this.interaction,
    required this.onBack,
    required this.onMinimize,
    required this.onRotate,
    this.attachVideo = true,
    this.isDesktop = false,
    this.isFullScreen = false,
    this.onToggleFullScreen,
    this.onEscape,
  });

  final PlayerController controller;
  final PlayerInteractionController interaction;
  final VoidCallback onBack;
  final VoidCallback onMinimize;
  final VoidCallback? onRotate;
  final bool isDesktop;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final VoidCallback? onEscape;

  /// 为 false 时释放纹理给小窗，避免与 [MiniPlayerOverlay] 双挂载。
  final bool attachVideo;

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): controller.togglePlay,
      const SingleActivator(LogicalKeyboardKey.keyK): controller.togglePlay,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          controller.seekBy(-10),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          controller.seekBy(10),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          controller.setLocalVolume(controller.volume + 0.05),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          controller.setLocalVolume(controller.volume - 0.05),
      const SingleActivator(LogicalKeyboardKey.keyM): controller.toggleMute,
      const SingleActivator(LogicalKeyboardKey.escape): onEscape ?? onBack,
    };
    final toggleFullScreen = onToggleFullScreen;
    if (toggleFullScreen != null) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyF)] =
          toggleFullScreen;
    }
    return CallbackShortcuts(
      bindings: isDesktop
          ? shortcuts
          : const <ShortcutActivator, VoidCallback>{},
      child: Focus(
        autofocus: isDesktop,
        child: _PlayerPointerRegion(
          controller: controller,
          isDesktop: isDesktop,
          isFullScreen: isFullScreen,
          child: ColoredBox(
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
                PlayerGestureLayer(
                  interaction: interaction,
                  desktop: isDesktop,
                  onDesktopDoubleTap: onToggleFullScreen,
                ),
                PlayerFeedbackHud(interaction: interaction),
                _PlayerDynamicOverlay(
                  controller: controller,
                  onBack: onBack,
                  onMinimize: onMinimize,
                  onRotate: onRotate,
                  isDesktop: isDesktop,
                  isFullScreen: isFullScreen,
                  onToggleFullScreen: onToggleFullScreen,
                ),
              ],
            ),
          ),
        ),
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
    required this.isDesktop,
    required this.isFullScreen,
    required this.onToggleFullScreen,
  });

  final PlayerController controller;
  final VoidCallback onBack;
  final VoidCallback onMinimize;
  final VoidCallback? onRotate;
  final bool isDesktop;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;

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
                        isDesktop: isDesktop,
                        isFullScreen: isFullScreen,
                        onToggleFullScreen: onToggleFullScreen,
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

// 单独监听控制层显隐，鼠标移动与光标更新不会重建视频纹理。
class _PlayerPointerRegion extends StatefulWidget {
  const _PlayerPointerRegion({
    required this.controller,
    required this.isDesktop,
    required this.isFullScreen,
    required this.child,
  });

  final PlayerController controller;
  final bool isDesktop;
  final bool isFullScreen;
  final Widget child;

  @override
  State<_PlayerPointerRegion> createState() => _PlayerPointerRegionState();
}

class _PlayerPointerRegionState extends State<_PlayerPointerRegion> {
  late bool _controlsVisible;

  @override
  void initState() {
    super.initState();
    _controlsVisible = widget.controller.controlsVisible;
    widget.controller.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant _PlayerPointerRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_sync);
    _controlsVisible = widget.controller.controlsVisible;
    widget.controller.addListener(_sync);
  }

  void _sync() {
    final visible = widget.controller.controlsVisible;
    if (!mounted || visible == _controlsVisible) return;
    setState(() => _controlsVisible = visible);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.isDesktop && widget.isFullScreen && !_controlsVisible
        ? SystemMouseCursors.none
        : SystemMouseCursors.basic,
    onHover: widget.isDesktop ? (_) => widget.controller.showControls() : null,
    child: widget.child,
  );
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: extras.onPlayerInk),
              const SizedBox(height: LumaSpacing.md),
              Text(
                _buffering ? '正在缓冲' : '正在准备播放',
                textAlign: TextAlign.center,
                style: TextStyle(color: extras.onPlayerInkMuted),
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
