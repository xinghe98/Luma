import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';
import '../player_interaction_controller.dart';
import 'player_controls.dart';
import 'player_feedback_hud.dart';
import 'player_gesture_layer.dart';
import 'player_timeline.dart';
import 'player_video_surface.dart';
import 'tv_player_controls.dart';

class PlayerScene extends StatelessWidget {
  /// 组合视频、反馈和控制；桌面端额外提供键盘、鼠标与窗口全屏，
  /// TV 分支改用遥控按键契约与专用控制层，不挂手机手势层。
  const PlayerScene({
    super.key,
    required this.controller,
    required this.interaction,
    required this.onBack,
    this.onMinimize,
    required this.onRotate,
    this.attachVideo = true,
    this.isDesktop = false,
    this.isFullScreen = false,
    this.onToggleFullScreen,
    this.onEscape,
    this.isTelevision = false,
  });

  final PlayerController controller;
  final PlayerInteractionController interaction;
  final VoidCallback onBack;

  /// 收起到应用内小窗；TV 没有小窗播放，传 null。
  final VoidCallback? onMinimize;
  final VoidCallback? onRotate;
  final bool isDesktop;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final VoidCallback? onEscape;

  /// 当前是否为 TV 形态；TV 复用同一个视频 surface，仅替换输入层与控制层。
  final bool isTelevision;

  /// 为 false 时释放纹理给小窗，避免与 [MiniPlayerOverlay] 双挂载。
  final bool attachVideo;

  @override
  Widget build(BuildContext context) {
    if (isTelevision) {
      return _TvPlayerScene(
        controller: controller,
        interaction: interaction,
        onBack: onBack,
        onEscape: onEscape ?? onBack,
        attachVideo: attachVideo,
      );
    }
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
                  isTelevision: isTelevision,
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
    required this.isTelevision,
    this.isDesktop = false,
    this.isFullScreen = false,
    this.onToggleFullScreen,
    this.onSpeedDialogChanged,
  });

  final PlayerController controller;
  final VoidCallback onBack;

  /// 收起到小窗；TV 没有小窗播放，恒为 null。
  final VoidCallback? onMinimize;
  final VoidCallback? onRotate;
  final bool isTelevision;
  final bool isDesktop;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;
  final ValueChanged<bool>? onSpeedDialogChanged;

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
                    // TV 隐藏的控制层不参与焦点与语义，避免遥控器选中看不见的控件。
                    child: ExcludeFocus(
                      excluding: !controlsVisible,
                      child: ExcludeSemantics(
                        excluding: !controlsVisible,
                        child: SafeArea(
                          child: isTelevision
                              ? TvPlayerControls(
                                  controller: controller,
                                  onClose: onBack,
                                  onSpeedDialogChanged: onSpeedDialogChanged,
                                )
                              : PlayerControls(
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

// TV 播放器输入层：拥有播放器输入根焦点，并按控制层显隐切换按键绑定。
// 控制层隐藏时确认键切换播放、左右快进快退并显示短暂时间反馈、上下仅显示
// 控制层；控制层可见时方向键交给默认焦点遍历，确认键只激活聚焦中的控件。
// 系统音量/静音/Home 不在此截获；Back 由页面的单一 PopScope 状态判定处理。
class _TvPlayerScene extends StatefulWidget {
  const _TvPlayerScene({
    required this.controller,
    required this.interaction,
    required this.onBack,
    required this.onEscape,
    required this.attachVideo,
  });

  final PlayerController controller;
  final PlayerInteractionController interaction;
  final VoidCallback onBack;
  final VoidCallback onEscape;

  /// 为 false 时释放纹理给小窗；TV 无小窗，恒为 true。
  final bool attachVideo;

  @override
  State<_TvPlayerScene> createState() => _TvPlayerSceneState();
}

class _TvPlayerSceneState extends State<_TvPlayerScene> {
  late FocusNode _inputRoot;
  bool _controlsShown = true;
  late bool _useVisibleBindings;
  bool _wasPlaying = false;
  bool _speedDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _inputRoot = FocusNode(
      skipTraversal: true,
      debugLabel: 'tvPlayerInputRoot',
    );
    _controlsShown = widget.controller.controlsVisible;
    _useVisibleBindings =
        widget.controller.controlsVisible || widget.controller.error != null;
    _wasPlaying = widget.controller.playing;
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant _TvPlayerScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChange);
    _controlsShown = widget.controller.controlsVisible;
    _useVisibleBindings =
        widget.controller.controlsVisible || widget.controller.error != null;
    _wasPlaying = widget.controller.playing;
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _inputRoot.dispose();
    super.dispose();
  }

  /// 暂停与错误期间保持控制层可见：其他操作在帧内重启的自动隐藏计时
  /// 统一在帧末取消；速度弹窗打开期间保持暂停计时。控制层隐藏时把焦点
  /// 交还播放器输入根，显示侧的播放按钮聚焦由 TvPlayerControls 完成。
  /// 只有按键模式变化才重建场景；位置和缓冲通知由局部控件消费。
  void _handleControllerChange() {
    final shown = widget.controller.controlsVisible;
    final playing = widget.controller.playing;
    final useVisibleBindings = shown || widget.controller.error != null;
    if (useVisibleBindings != _useVisibleBindings) {
      setState(() => _useVisibleBindings = useVisibleBindings);
    }
    if (playing != _wasPlaying) {
      _wasPlaying = playing;
      if (playing && !_speedDialogOpen) widget.controller.scheduleHide();
    }
    if (_speedDialogOpen || !playing || widget.controller.error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_speedDialogOpen ||
            !widget.controller.playing ||
            widget.controller.error != null) {
          widget.controller.pauseAutoHide();
        }
      });
    }
    if (shown == _controlsShown) return;
    _controlsShown = shown;
    if (!shown) _inputRoot.requestFocus();
  }

  /// 媒体键保持控制层显隐现状：可见时重置自动隐藏计时，隐藏时不强行显示。
  void _togglePlayQuietly() => widget.controller.togglePlay(
    revealControls: widget.controller.controlsVisible,
  );

  /// 媒体播放键仅在未播放时启动，不打断当前播放。
  void _playIfPaused() {
    if (widget.controller.playing) return;
    _togglePlayQuietly();
  }

  void _pauseQuietly() => unawaited(
    widget.controller.pause(revealControls: widget.controller.controlsVisible),
  );

  /// 媒体快进快退：控制层可见时保持原样；隐藏时只露出进度条，不打开按钮层。
  void _seekByMediaKey(int seconds) {
    final visible = widget.controller.controlsVisible;
    widget.controller.seekBy(seconds, revealControls: visible);
    if (!visible) {
      widget.interaction.showSeekFeedback(forward: seconds > 0);
    }
  }

  /// 控制层隐藏时的快进快退：不打开按钮层、不移动焦点，只露出进度条。
  void _seekWithFeedback(int seconds) {
    widget.controller.seekBy(seconds, revealControls: false);
    widget.interaction.showSeekFeedback(forward: seconds > 0);
  }

  /// 控制层隐藏时的确认键：切换播放/暂停并显示控制层，焦点由控制层
  /// 显隐监听落到播放按钮；一次按键一次动作。
  void _confirmWhileHidden() => widget.controller.togglePlay();

  /// 仅显示控制层并聚焦播放按钮，不修改音量。
  void _revealControls() => widget.controller.showControls();

  /// 媒体键在控制层显隐两种状态下都可用；快进/快退允许重复事件。
  Map<ShortcutActivator, Intent> get _mediaKeyBindings => {
    const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
        VoidCallbackIntent(_togglePlayQuietly),
    const SingleActivator(
      LogicalKeyboardKey.mediaPlayPause,
      includeRepeats: false,
    ): VoidCallbackIntent(
      _togglePlayQuietly,
    ),
    const SingleActivator(LogicalKeyboardKey.mediaPlay, includeRepeats: false):
        VoidCallbackIntent(_playIfPaused),
    const SingleActivator(LogicalKeyboardKey.mediaPause, includeRepeats: false):
        VoidCallbackIntent(_pauseQuietly),
    const SingleActivator(LogicalKeyboardKey.mediaRewind): VoidCallbackIntent(
      () => _seekByMediaKey(-10),
    ),
    const SingleActivator(LogicalKeyboardKey.mediaFastForward):
        VoidCallbackIntent(() => _seekByMediaKey(10)),
  };

  Map<ShortcutActivator, Intent> get _hiddenBindings => {
    ..._mediaKeyBindings,
    // 确认键忽略 repeat，长按 OK 不会反复切换播放。
    const SingleActivator(LogicalKeyboardKey.select, includeRepeats: false):
        VoidCallbackIntent(_confirmWhileHidden),
    const SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
        VoidCallbackIntent(_confirmWhileHidden),
    const SingleActivator(
      LogicalKeyboardKey.numpadEnter,
      includeRepeats: false,
    ): VoidCallbackIntent(
      _confirmWhileHidden,
    ),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): VoidCallbackIntent(
      () => _seekWithFeedback(-10),
    ),
    const SingleActivator(LogicalKeyboardKey.arrowRight): VoidCallbackIntent(
      () => _seekWithFeedback(10),
    ),
    const SingleActivator(LogicalKeyboardKey.arrowUp): VoidCallbackIntent(
      _revealControls,
    ),
    const SingleActivator(LogicalKeyboardKey.arrowDown): VoidCallbackIntent(
      _revealControls,
    ),
    const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
        VoidCallbackIntent(widget.onEscape),
  };

  Map<ShortcutActivator, Intent> get _visibleBindings => {
    ..._mediaKeyBindings,
    // 方向键不在此绑定：交给默认焦点遍历在控制按钮与进度条间移动，
    // 不会触发整页 seek/音量快捷键。
    const SingleActivator(LogicalKeyboardKey.select, includeRepeats: false):
        const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
        const ActivateIntent(),
    const SingleActivator(
      LogicalKeyboardKey.numpadEnter,
      includeRepeats: false,
    ): const ActivateIntent(),
    const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
        VoidCallbackIntent(widget.onEscape),
  };

  /// 消费确认长按，防止落入默认激活；方向遍历同时延长可见控制层的计时。
  KeyEventResult _handleInputKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyRepeatEvent &&
        const [
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.numpadEnter,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.mediaPlayPause,
          LogicalKeyboardKey.mediaPlay,
          LogicalKeyboardKey.mediaPause,
        ].contains(key)) {
      return KeyEventResult.handled;
    }
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        const [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ].contains(key) &&
        widget.controller.controlsVisible &&
        widget.controller.playing &&
        widget.controller.error == null) {
      widget.controller.scheduleHide();
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _useVisibleBindings ? _visibleBindings : _hiddenBindings,
      child: Focus(
        focusNode: _inputRoot,
        skipTraversal: true,
        onKeyEvent: _handleInputKey,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: PlayerVideoSurface(
                  controller: widget.controller,
                  attachVideo: widget.attachVideo,
                  keepAwake: true,
                ),
              ),
              // 带鼠标的盒子：点击视频区域切换控制层；不挂手机手势层。
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.interaction.handleTap,
              ),
              PlayerFeedbackHud(interaction: widget.interaction),
              _TvSeekTimelinePeek(
                controller: widget.controller,
                interaction: widget.interaction,
              ),
              _PlayerDynamicOverlay(
                controller: widget.controller,
                onBack: widget.onBack,
                onMinimize: null,
                onRotate: null,
                isTelevision: true,
                onSpeedDialogChanged: (open) => _speedDialogOpen = open,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 快进快退时只在底部露出进度，位置刷新不重建视频纹理，焦点留在输入根上。
class _TvSeekTimelinePeek extends StatelessWidget {
  const _TvSeekTimelinePeek({
    required this.controller,
    required this.interaction,
  });

  final PlayerController controller;
  final PlayerInteractionController interaction;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, interaction]),
      builder: (context, _) {
        final kind = interaction.hudKind;
        final show =
            !controller.controlsVisible &&
            controller.error == null &&
            interaction.hudVisible &&
            (kind == PlayerHudKind.forward ||
                kind == PlayerHudKind.backward ||
                kind == PlayerHudKind.seek);
        if (!show) return const SizedBox.shrink();
        return IgnorePointer(
          child: ExcludeFocus(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LumaSpacing.xl,
                    0,
                    LumaSpacing.xl,
                    LumaSpacing.lg,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: PlayerTimeline(
                      key: const ValueKey('tv-seek-timeline'),
                      controller: controller,
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
}
