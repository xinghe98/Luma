import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../shell/app_destination.dart';
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
  PlayerSystemUiSession? _systemUi;
  bool _resolved = false;
  bool _isTelevision = false;

  /// TV 后台暂停意图：控制器尚未创建（深链加载中）也生效，
  /// 创建控制器后立即施加暂停；返回前台不自动清除。
  bool _tvMustStartPaused = false;
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
    // 首次解析依赖时确定设备形态，系统 UI 会话随之创建；
    // 无 initialItem 的加载/错误路径同样先完成该初始化。
    final dependencies = AppScope.of(context);
    _isTelevision = dependencies.deviceProfile.isTelevision;
    _systemUi = PlayerSystemUiSession(television: _isTelevision);
    if (_isTelevision) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
        _tvMustStartPaused = true;
      }
    }
    final media = dependencies.media;
    final session = dependencies.playerSession;
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
    if (_isTelevision && _tvMustStartPaused) {
      // 后台事件先于控制器创建到达：起播立即施加暂停，不自动出声。
      unawaited(controller.pause(revealControls: false));
    }
    final interaction = PlayerInteractionController(
      player: controller,
      deviceControls: const MethodChannelPlayerDeviceControls(),
    );
    _controller = controller;
    _session = session;
    _interaction = interaction;
    // TV 不读取系统亮度与软件音量，跳过设备状态初始化与恢复。
    if (!_isTelevision) unawaited(interaction.initialize());
    final mediaQuery = MediaQuery.of(context);
    unawaited(
      _enterPresentation(
        item: item,
        orientation: mediaQuery.orientation,
        shortestSide: mediaQuery.size.shortestSide,
      ),
    );
  }

  /// 进入当前平台的播放器呈现模式，并同步桌面全屏状态；TV 会话内部为空操作。
  Future<void> _enterPresentation({
    required MediaItem item,
    required Orientation orientation,
    required double shortestSide,
  }) async {
    final systemUi = _systemUi;
    if (systemUi == null) return;
    await systemUi.enter(
      portraitVideo: item.isPortrait,
      entryOrientation: orientation,
      shortestSide: shortestSide,
    );
    if (mounted && _fullscreen != systemUi.fullScreen) {
      setState(() => _fullscreen = systemUi.fullScreen);
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
      // TV 从未初始化设备状态（亮度/软件音量），同样跳过恢复。
      if (!_isTelevision) unawaited(interaction.restoreDeviceState());
      interaction.dispose();
    }
    _controller = null;
    _session = null;
    unawaited(_systemUi?.exit());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_isTelevision) {
        // TV 后台即暂停：先记录意图（控制器未创建也生效），进度由 pause
        // 保存，不额外发一份 persistProgress；返回前台保持暂停，OK 才继续。
        _tvMustStartPaused = true;
        unawaited(_controller?.pause(revealControls: false));
        return;
      }
      unawaited(_controller?.persistProgress());
      unawaited(_interaction?.restoreDeviceState());
    } else if (state == AppLifecycleState.resumed) {
      // TV 保持暂停，等待用户确认键继续；不自动恢复设备状态轮询。
      if (_isTelevision) return;
      unawaited(_interaction?.initialize());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final interaction = _interaction;
    final systemUi = _systemUi;
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
        // TV 返回由单一 PopScope 状态判定分层处理，与键盘 Escape 共用逻辑。
        television: _isTelevision,
        onBackRequested: _handleTvBack,
        child: PlayerScene(
          controller: controller,
          interaction: interaction,
          // 收起过程中先卸下全屏纹理，再交给小窗挂载，避免双绑定。
          attachVideo: !_minimizing,
          onBack: _closeAndPop,
          onMinimize: _isTelevision ? null : _minimizeAndPop,
          onRotate: systemUi != null && systemUi.canRotate
              ? () => unawaited(systemUi.rotate())
              : null,
          isTelevision: _isTelevision,
          isDesktop: systemUi?.isDesktop ?? false,
          isFullScreen: _fullscreen,
          onToggleFullScreen: systemUi != null && systemUi.isDesktop
              ? () => unawaited(_toggleFullScreen())
              : null,
          onEscape: systemUi != null && systemUi.isDesktop
              ? () => unawaited(_handleEscape())
              : _isTelevision
              ? _handleTvBack
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

  /// 正常返回会结束播放，避免未明确收起时继续占用解码器；
  /// 深链播放器没有来源栈时回首页，不停留在无法退出的页面。
  void _closeAndPop() {
    unawaited(_session?.close());
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go(AppDestination.home.path);
  }

  /// TV 分层返回：速度弹窗打开时由其自身路由响应 Back；否则先隐藏可见
  /// 控制层，控制层已隐藏（或处于错误/初始化失败状态）才结束播放返回来源。
  /// 键盘 Escape 与 PopScope 共用本入口，避免双 pop。
  void _handleTvBack() {
    final controller = _controller;
    if (controller != null &&
        controller.controlsVisible &&
        controller.error == null) {
      controller.toggleControls();
      return;
    }
    _closeAndPop();
  }

  /// 切换 Windows 原生全屏，并刷新工具栏和光标状态。
  Future<void> _toggleFullScreen() async {
    final systemUi = _systemUi;
    if (systemUi == null) return;
    final fullscreen = await systemUi.toggleFullScreen();
    if (mounted && fullscreen != _fullscreen) {
      setState(() => _fullscreen = fullscreen);
    }
  }

  /// Escape 优先退出全屏，窗口模式下才关闭播放器页面。
  Future<void> _handleEscape() async {
    final systemUi = _systemUi;
    if (systemUi != null && await systemUi.exitFullScreen()) {
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
// TV 恒拦截系统返回，由 [onBackRequested] 分层处理（隐藏控制层 → 结束播放）。
class _PlayerPopGuard extends StatefulWidget {
  const _PlayerPopGuard({
    required this.controller,
    required this.minimizing,
    required this.onPopped,
    required this.child,
    this.television = false,
    this.onBackRequested,
  });

  final PlayerController controller;
  final bool minimizing;
  final VoidCallback onPopped;
  final Widget child;
  final bool television;
  final VoidCallback? onBackRequested;

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
    // TV 恒拦截返回，分层逻辑交给 onBackRequested；普通端锁定时拦截。
    canPop: widget.television ? false : !_locked,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) {
        if (!widget.minimizing) {
          widget.onPopped();
        }
        return;
      }
      if (widget.television) {
        widget.onBackRequested?.call();
        return;
      }
      widget.controller.showLockHint();
    },
    child: widget.child,
  );
}
