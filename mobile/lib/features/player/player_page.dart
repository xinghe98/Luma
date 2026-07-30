import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import 'player_controller.dart';
import 'player_device_controls.dart';
import 'player_interaction_controller.dart';
import 'player_session_controller.dart';
import 'player_system_ui.dart';
import 'widgets/player_scene.dart';

/// 播放指定媒体，并可选择忽略已保存的续播进度。
class PlayerPage extends StatefulWidget {
  /// 打开指定媒体；有首帧条目时立即启动，否则在本页加载并保留重试路径。
  const PlayerPage({
    super.key,
    required this.mediaId,
    this.initialItem,
    this.startFromBeginning = false,
  });

  final String mediaId;
  final MediaItem? initialItem;
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
  bool _loading = false;
  bool _fullscreen = false;
  String? _loadError;
  int _loadGeneration = 0;

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
        (widget.initialItem?.id == widget.mediaId
            ? widget.initialItem
            : null) ??
        media.findById(widget.mediaId) ??
        (active?.item.id == widget.mediaId ? active!.item : null);
    if (item == null) {
      _loading = true;
      _loadMedia();
      return;
    }
    media.remember(item, notify: false);
    _startPlayer(item, session);
  }

  /// 创建或复用播放会话，并初始化当前页面独有的设备交互与系统 UI。
  void _startPlayer(MediaItem item, PlayerSessionController session) {
    if (_controller != null) return;
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
      _enterPresentation(
        item: item,
        orientation: mediaQuery.orientation,
        shortestSide: mediaQuery.size.shortestSide,
      ),
    );
  }

  /// 进入当前平台的播放器呈现模式，并同步桌面全屏状态。
  Future<void> _enterPresentation({
    required MediaItem item,
    required Orientation orientation,
    required double shortestSide,
  }) async {
    await _systemUi.enter(
      portraitVideo: item.isPortrait,
      entryOrientation: orientation,
      shortestSide: shortestSide,
    );
    if (mounted && _fullscreen != _systemUi.fullScreen) {
      setState(() => _fullscreen = _systemUi.fullScreen);
    }
  }

  /// 深链无缓存时读取媒体；失败保留播放器尺寸和返回操作，并允许原地重试。
  Future<void> _loadMedia() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    final dependencies = AppScope.of(context);
    await dependencies.media.loadDetail(widget.mediaId);
    if (!mounted || generation != _loadGeneration) return;
    final item = dependencies.media.findById(widget.mediaId);
    if (item == null) {
      setState(() {
        _loading = false;
        _loadError = dependencies.media.detailError ?? '找不到该媒体，可能已被移除。';
      });
      return;
    }
    _startPlayer(item, dependencies.playerSession);
    setState(() {
      _loading = false;
      _loadError = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadGeneration++;
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
      return _PlayerRouteLoadingState(
        loading: _loading,
        error: _loadError,
        onRetry: _loadMedia,
      );
    }
    return Scaffold(
      backgroundColor: extras.playerInk,
      body: _PlayerPopGuard(
        controller: controller,
        minimizing: _minimizing,
        onPopped: () => unawaited(_session?.close()),
        child: PlayerScene(
          controller: controller,
          interaction: interaction,
          // 收起过程中先卸下全屏纹理，再交给小窗挂载，避免双绑定。
          attachVideo: !_minimizing,
          onBack: _closeAndPop,
          onMinimize: _minimizeAndPop,
          onRotate: _systemUi.canRotate
              ? () => unawaited(_systemUi.rotate())
              : null,
          isDesktop: _systemUi.isDesktop,
          isFullScreen: _fullscreen,
          onToggleFullScreen: _systemUi.isDesktop
              ? () => unawaited(_toggleFullScreen())
              : null,
          onEscape: _systemUi.isDesktop
              ? () => unawaited(_handleEscape())
              : null,
        ),
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

  /// 切换 Windows 原生全屏，并刷新工具栏和光标状态。
  Future<void> _toggleFullScreen() async {
    final fullscreen = await _systemUi.toggleFullScreen();
    if (mounted && fullscreen != _fullscreen) {
      setState(() => _fullscreen = fullscreen);
    }
  }

  /// Escape 优先退出全屏，窗口模式下才关闭播放器页面。
  Future<void> _handleEscape() async {
    if (await _systemUi.exitFullScreen()) {
      if (mounted) setState(() => _fullscreen = false);
      return;
    }
    if (mounted) _closeAndPop();
  }
}

class _PlayerRouteLoadingState extends StatelessWidget {
  const _PlayerRouteLoadingState({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    return Scaffold(
      backgroundColor: extras.playerInk,
      appBar: AppBar(
        backgroundColor: extras.playerInk,
        foregroundColor: extras.onPlayerInk,
        title: const Text('播放器'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (loading)
            Semantics(
              label: '正在加载媒体',
              liveRegion: true,
              child: const Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(LumaSpacing.lg),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error ?? '找不到该媒体，可能已被移除。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: extras.onPlayerInkMuted),
                      ),
                      const SizedBox(height: LumaSpacing.md),
                      FilledButton(onPressed: onRetry, child: const Text('重试')),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// 仅在锁定状态变化时重建 PopScope，播放进度更新不会重建整个视频场景。
class _PlayerPopGuard extends StatefulWidget {
  const _PlayerPopGuard({
    required this.controller,
    required this.minimizing,
    required this.onPopped,
    required this.child,
  });

  final PlayerController controller;
  final bool minimizing;
  final VoidCallback onPopped;
  final Widget child;

  @override
  State<_PlayerPopGuard> createState() => _PlayerPopGuardState();
}

class _PlayerPopGuardState extends State<_PlayerPopGuard> {
  late bool _locked;

  @override
  void initState() {
    super.initState();
    _locked = widget.controller.locked;
    widget.controller.addListener(_syncLock);
  }

  @override
  void didUpdateWidget(covariant _PlayerPopGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_syncLock);
    _locked = widget.controller.locked;
    widget.controller.addListener(_syncLock);
  }

  void _syncLock() {
    final locked = widget.controller.locked;
    if (locked == _locked || !mounted) return;
    setState(() => _locked = locked);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncLock);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_locked,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop && !widget.minimizing) {
        widget.onPopped();
      } else if (_locked) {
        widget.controller.showLockHint();
      }
    },
    child: widget.child,
  );
}
