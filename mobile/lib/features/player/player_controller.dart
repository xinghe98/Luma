// 播放控制器封装视频解码、播放状态、交互状态与进度持久化。
// 初始化和重试使用 generation 丢弃旧回包，销毁后不再更新任何可见状态。
// 所有定位入口（快进、拖动提交、取消回起点、回到开头）共用一条等待链路：
// 命令被原生接受后读取 mpv `seeking` 与当前 time-pos 判定定位是否结束，
// 原生缓冲事件独立叠加展示，等待期间屏蔽过时位置，
// 被取代或已释放请求的异步续作不会写回新会话。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/api/api_session.dart';
import '../../data/proxy/loopback_media_relay.dart';
import '../../data/models/media_item.dart';

class PlayerController extends ChangeNotifier {
  /// 创建播放控制器；startFromBeginning 为 true 时不读取既有进度。
  PlayerController({
    required this.item,
    required MediaController media,
    ApiSession? apiSession,
    MediaRequestRouter? mediaRequestRouter,
    this.startFromBeginning = false,
    this.autoHideDelay = const Duration(seconds: 4),
    this.bufferingTimeout = const Duration(seconds: 45),
    this.initializationTimeout = const Duration(seconds: 20),
    @visibleForTesting this.debugPlatformPlayerFactory,
    @visibleForTesting this.debugVideoControllerFactory,
  }) : _media = media,
       _apiSession = apiSession,
       _mediaRequestRouter =
           mediaRequestRouter ?? const DirectMediaRequestRouter(),
       _startAtZero = startFromBeginning,
       _pendingResumePosition = startFromBeginning || item.progress <= 0
           ? null
           : item.duration * item.progress,
       _position = startFromBeginning
           ? Duration.zero
           : item.duration * item.progress;

  final MediaItem item;
  final MediaController _media;
  final ApiSession? _apiSession;
  final MediaRequestRouter _mediaRequestRouter;
  final bool startFromBeginning;
  final Duration autoHideDelay;
  final Duration bufferingTimeout;

  /// 初始化播放器等待底层属性、媒体和首个播放命令完成的最长时间。
  final Duration initializationTimeout;

  /// 测试注入底层播放器创建方式；为空时由 media_kit 按平台创建。
  @visibleForTesting
  final PlatformPlayer Function(PlayerConfiguration configuration)?
  debugPlatformPlayerFactory;

  /// 测试注入视频控制器创建方式；返回 null 时只验证播放状态，不创建纹理。
  @visibleForTesting
  final VideoController? Function(Player player)? debugVideoControllerFactory;

  /// 位置与目标相差不超过此值视为已到位：同位置定位或精确定位落地都属这种情况。
  /// 仅当命令已被原生接受且原生报告不再定位时才用它收束，更远的位置不驱动滑块。
  static const Duration seekLandingTolerance = Duration(seconds: 1);

  /// NativePlayer 在 Android 与 Windows 共用的首播和再缓冲策略。
  @visibleForTesting
  static const Map<String, String> nativeBufferingProperties = {
    'network-timeout': '60',
    'force-seekable': 'yes',
    'demuxer-readahead-secs': '2',
    'cache-pause-initial': 'no',
    'cache-pause': 'yes',
    'cache-pause-wait': '3',
  };

  bool _startAtZero;
  Duration? _pendingResumePosition;
  late Duration _position;
  Timer? _hideTimer;
  Timer? _saveTimer;
  Timer? _syncThrottle;
  Timer? _lockHintTimer;
  Timer? _initializationWatchdog;
  Timer? _bufferingWatchdog;
  _SeekRequest? _seekRequest;
  _SeekRequest? _dispatchingSeek;
  bool _nativeBuffering = false;
  Duration? _nativePosition;
  Player? _player;
  VideoController? _videoController;
  final List<Player> _disposingPlayers = [];
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];
  String? _mediaRouteToken;
  String? _error;
  bool _disposed = false;
  bool _initialized = false;
  bool _buffering = false;
  bool _playing = false;
  bool _controlsVisible = true;
  bool _locked = false;
  bool _initializationFailed = false;
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  Duration? _scrubOrigin;

  /// 拖动开始时是否已有下发过的定位，用于取消拖动后把底层拉回起点。
  bool _scrubNativeMoved = false;
  double _speed = 1;
  double _volume = 1;
  double _volumeBeforeMute = 1;
  bool _muted = false;
  int _initializationGeneration = 0;

  Duration get position => _position;
  bool get playing => _playing;
  bool get controlsVisible => _controlsVisible;
  bool get locked => _locked;
  double get speed => _speed;

  /// 播放器内部音量，范围为 0 到 1。
  double get volume => _volume;

  /// 当前是否静音；零音量同样视为静音。
  bool get muted => _muted;
  bool get initialized => _initialized;
  bool get buffering => _buffering;
  bool get scrubbing => _scrubbing;
  String? get error => _error;
  VideoController? get videoController => _videoController;

  /// 当前可接受命令的底层播放器；未初始化或已释放时为 null。
  Player? get _commandPlayer {
    if (_disposed || !_initialized) return null;
    return _player;
  }

  /// 是否已发起初始化且尚未结束（成功或失败都会结束该阶段）。
  bool get _isInitializing => _initializationWatchdog != null;

  /// 返回可用于展示和进度计算的总时长；播放器尚未取得流元数据时回退到扫描结果。
  Duration get duration {
    final nativeDuration = _player?.state.duration ?? Duration.zero;
    return nativeDuration > Duration.zero ? nativeDuration : item.duration;
  }

  /// 启动播放与定时保存；可播放地址缺失时保留错误供用户重试。
  void start() {
    final session = _apiSession;
    final streamUrl = item.streamUrl;
    if (item.status != 'ready') {
      _error = '媒体尚未就绪，当前状态：${item.status}';
      notifyListeners();
    } else if (session != null && streamUrl != null && streamUrl.isNotEmpty) {
      unawaited(_initializeVideo(session, streamUrl));
    } else if (session != null) {
      _error = '服务端未返回可播放的视频流地址';
      notifyListeners();
    }
    _saveTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      // 暂停后的进度已在暂停动作中保存。继续定时写入相同位置会
      // 触发不必要的网络请求和全局媒体状态更新。
      (_) {
        if (_playing) unawaited(_saveProgress());
      },
    );
    scheduleHide();
  }

  Future<void> _initializeVideo(ApiSession session, String streamUrl) async {
    final generation = ++_initializationGeneration;
    _armInitializationWatchdog(generation);
    try {
      final access = session.resolveResource(streamUrl);
      _mediaRequestRouter.revoke(_mediaRouteToken);
      _mediaRouteToken = null;
      final previous = _player;
      _player = null;
      _videoController = null;
      _initialized = false;
      _resetSeekState();
      _bufferingWatchdog?.cancel();
      _bufferingWatchdog = null;
      await _cancelPlayerSubscriptions();
      if (previous != null) await _disposePlayer(previous);
      if (_disposed || generation != _initializationGeneration) return;

      final configuration = const PlayerConfiguration(
        title: '轻影',
        bufferSize: 64 * 1024 * 1024,
      );
      final player = Player(
        configuration: configuration,
        platformPlayer: debugPlatformPlayerFactory?.call(configuration),
      );
      _player = player;
      final videoControllerFactory = debugVideoControllerFactory;
      _videoController = videoControllerFactory != null
          ? videoControllerFactory(player)
          : VideoController(player);
      _listenToPlayer(player, generation);

      final platform = player.platform;
      if (platform is NativePlayer) {
        for (final entry in nativeBufferingProperties.entries) {
          await platform.setProperty(entry.key, entry.value);
        }
      }
      // 原生定位状态是定位结束的主要判据；非原生实现会直接返回并退化为位置事件。
      unawaited(_observeSeeking(player));
      if (_disposed || generation != _initializationGeneration) {
        await _disposePlayer(player);
        return;
      }
      final mediaRoute = _mediaRequestRouter.route(access.url, access.headers);
      _mediaRouteToken = mediaRoute.token;
      final initial = _startAtZero ? Duration.zero : _position;
      _pendingResumePosition = initial > Duration.zero ? initial : null;
      await player.open(
        Media(
          mediaRoute.url,
          httpHeaders: mediaRoute.headers,
          start: _pendingResumePosition,
        ),
        play: false,
      );
      if (_disposed || generation != _initializationGeneration) {
        await _disposePlayer(player);
        return;
      }
      await player.setVolume(_volume * 100);
      await player.play();
      if (_disposed || generation != _initializationGeneration) return;
      _initializationWatchdog?.cancel();
      _initializationWatchdog = null;
      _startAtZero = false;
      _initialized = true;
      _initializationFailed = false;
      _error = null;
      _playing = true;
      _refreshBuffering(armWatchdog: true);
      // 初始化期间用户仍可快进或拖动，起播后补发他们最后一次选择的位置。
      _dispatchLatestSeek();
      notifyListeners();
    } on Object catch (error) {
      if (_disposed || generation != _initializationGeneration) return;
      _collapseInitialization(generation, error.toString());
    }
  }

  void _armInitializationWatchdog(int generation) {
    _initializationWatchdog?.cancel();
    _initializationWatchdog = Timer(initializationTimeout, () {
      if (_disposed ||
          generation != _initializationGeneration ||
          _initialized) {
        return;
      }
      _collapseInitialization(generation, '视频准备时间过长，请重试');
    });
  }

  void _invalidateInitializationGeneration() {
    _initializationGeneration++;
    _initializationWatchdog?.cancel();
    _initializationWatchdog = null;
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
    _resetSeekState();
  }

  /// 初始化失败或超时时收束资源，先撤销旧会话，再异步释放底层播放器。
  void _collapseInitialization(int generation, String error) {
    if (_disposed || generation != _initializationGeneration) return;
    _initializationGeneration++;
    _initializationWatchdog?.cancel();
    _initializationWatchdog = null;
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
    _mediaRequestRouter.revoke(_mediaRouteToken);
    _syncThrottle?.cancel();
    _syncThrottle = null;
    _mediaRouteToken = null;
    final player = _player;
    _player = null;
    _videoController = null;
    _detachPlayerSubscriptions();
    _initialized = false;
    _initializationFailed = true;
    _resetSeekState();
    _playing = false;
    _error = error;
    if (player != null) unawaited(_disposePlayer(player));
    notifyListeners();
  }

  Future<void> _disposePlayer(Player player) async {
    if (_disposingPlayers.any((item) => identical(item, player))) {
      return;
    }
    _disposingPlayers.add(player);
    try {
      await player.dispose();
    } on Object {
      // 失败播放器已经脱离当前会话，释放失败不能阻止重试。
    } finally {
      _disposingPlayers.removeWhere((item) => identical(item, player));
    }
  }

  void _detachPlayerSubscriptions() {
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _playerSubscriptions,
    );
    _playerSubscriptions.clear();
    for (final subscription in subscriptions) {
      unawaited(_cancelSubscription(subscription));
    }
  }

  Future<void> _cancelSubscription(
    StreamSubscription<dynamic> subscription,
  ) async {
    try {
      await subscription.cancel();
    } on Object {
      // 订阅属于已失效播放器，取消失败不影响新会话。
    }
  }

  /// 订阅底层播放器状态，并用 generation 忽略已释放会话的异步事件。
  void _listenToPlayer(Player player, int generation) {
    _playerSubscriptions.addAll([
      player.stream.position.listen((value) {
        if (_disposed ||
            generation != _initializationGeneration ||
            _scrubbing) {
          return;
        }
        _handleNativePosition(value);
      }),
      player.stream.duration.listen((_) {
        if (_disposed || generation != _initializationGeneration) return;
        _notifyPlaybackState();
      }),
      player.stream.playing.listen((value) {
        if (_disposed || generation != _initializationGeneration) return;
        _playing = value;
        _notifyPlaybackState(immediate: true);
      }),
      player.stream.buffering.listen((value) {
        if (_disposed || generation != _initializationGeneration) return;
        _setBuffering(value);
        _notifyPlaybackState();
      }),
      player.stream.volume.listen((value) {
        if (_disposed || generation != _initializationGeneration) return;
        final volume = (value / 100).clamp(0.0, 1.0);
        if ((_volume - volume).abs() < 0.001) return;
        _volume = volume;
        _muted = volume <= 0.001;
        _notifyPlaybackState(immediate: true);
      }),
      player.stream.completed.listen((completed) {
        if (_disposed ||
            generation != _initializationGeneration ||
            !completed ||
            _scrubbing ||
            _seekRequest != null) {
          return;
        }
        _position = duration;
        unawaited(_saveProgress(forceEnd: true));
        _notifyPlaybackState(immediate: true);
      }),
      player.stream.error.listen((message) {
        if (_disposed || generation != _initializationGeneration) return;
        // 解码错误照实上报；等待中的定位一并结束，避免错误后还有续作恢复播放。
        _endPendingSeek();
        _error = message;
        _playing = false;
        _notifyPlaybackState(immediate: true);
      }),
    ]);
  }

  void _notifyPlaybackState({bool immediate = false}) {
    if (immediate) {
      _syncThrottle?.cancel();
      _syncThrottle = null;
      notifyListeners();
      return;
    }
    _syncThrottle ??= Timer(const Duration(milliseconds: 200), () {
      _syncThrottle = null;
      if (!_disposed) notifyListeners();
    });
  }

  /// 记录原生缓冲事件并刷新展示状态；已初始化时按需启动再缓冲超时。
  void _setBuffering(bool value, {bool armWatchdog = false}) {
    _nativeBuffering = value;
    _refreshBuffering(armWatchdog: value && (_initialized || armWatchdog));
  }

  /// 展示用缓冲状态由原生缓冲事件和等待中的定位共同决定；
  /// [armWatchdog] 为 true 且仍在等待时，用同一个 [bufferingTimeout] 做失败兜底。
  void _refreshBuffering({bool armWatchdog = false}) {
    final buffering = _nativeBuffering || _seekRequest != null;
    _buffering = buffering;
    if (!buffering) {
      _bufferingWatchdog?.cancel();
      _bufferingWatchdog = null;
      return;
    }
    if (!armWatchdog) return;
    _bufferingWatchdog?.cancel();
    final generation = _initializationGeneration;
    _bufferingWatchdog = Timer(bufferingTimeout, () {
      if (_disposed || generation != _initializationGeneration) return;
      _onBufferingTimedOut();
    });
  }

  /// 订阅底层定位状态（mpv `seeking` 的 yes/no）；测试可覆盖以注入原生信号。
  @protected
  Future<void> observeNativeSeeking(
    Player player,
    ValueChanged<bool> onChanged,
  ) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    await platform.observeProperty('seeking', (value) async {
      onChanged(value.trim() == 'yes');
    });
  }

  /// 读取命令被接受后的原生定位状态与当前播放位置；
  /// 返回 null 表示无法读取（非原生播放器），此时改用位置事件判据。
  @protected
  Future<({bool seeking, Duration? position})?> readNativeSeekState(
    Player player,
  ) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return null;
    final seeking = await platform.getProperty('seeking');
    final position = await platform.getProperty('time-pos');
    return (
      seeking: seeking.trim() == 'yes',
      position: _parseSeconds(position),
    );
  }

  Future<void> _observeSeeking(Player player) async {
    try {
      await observeNativeSeeking(
        player,
        (seeking) => _handleNativeSeeking(player, seeking),
      );
    } on Object {
      // 订阅失败退化为位置事件判据，不影响起播。
    }
  }

  /// 原生 `seeking` 事件只作为确认触发点：完成与否由命令被接受后的原生状态读取判定，
  /// 因此注册初值、被合并掉的 yes 或旧事件都不会误判定位完成。
  void _handleNativeSeeking(Player player, bool seeking) {
    if (_disposed || !identical(_player, player) || seeking) return;
    final request = _seekRequest;
    if (request == null) return;
    unawaited(_settleSeek(request, player));
  }

  /// 处理原生位置事件：等待定位期间不采信目标以外的位置（滑块不被拉走），
  /// 位置到达目标附近时再读取原生状态确认定位是否结束。
  void _handleNativePosition(Duration value) {
    _nativePosition = value;
    final request = _seekRequest;
    if (request != null) {
      // 定位期间的位置来自定位前的播放，不能驱动滑块，也不作为完成依据。
      if ((value - request.target).abs() > seekLandingTolerance) return;
      final player = request.player;
      if (player != null && request.commandAccepted) {
        unawaited(_settleSeek(request, player));
      }
    }
    syncPosition(value);
  }

  /// 结束等待：清空当前请求后，旧请求的异步续作都会因身份不匹配而失效。
  void _endPendingSeek() {
    _seekRequest = null;
    _refreshBuffering();
  }

  /// 会话切换时同时丢弃原生缓冲、定位状态与待完成的定位请求。
  void _resetSeekState() {
    _nativeBuffering = false;
    _dispatchingSeek = null;
    _nativePosition = null;
    _endPendingSeek();
  }

  bool _isCurrentSeek(_SeekRequest request) =>
      !_disposed && identical(_seekRequest, request);

  /// 命令接受后同时确认原生已结束定位且到达最新目标，旧 seek 的结束事件不能清除等待。
  Future<void> _settleSeek(_SeekRequest request, Player player) async {
    if (!_isCurrentSeek(request) || !request.commandAccepted) return;
    ({bool seeking, Duration? position})? state;
    try {
      state = await readNativeSeekState(player);
    } on Object {
      state = null;
    }
    if (!_isCurrentSeek(request) || !request.commandAccepted) return;
    if (state == null) {
      // 读不到原生状态（非原生播放器）时退化为：命令已接受且位置已到目标附近。
      final landed = _nativePosition;
      if (landed != null &&
          (landed - request.target).abs() <= seekLandingTolerance) {
        _completePendingSeek(request);
      }
      return;
    }
    if (state.seeking) return;
    final landed = state.position;
    if (landed == null ||
        (landed - request.target).abs() > seekLandingTolerance) {
      return;
    }
    _completePendingSeek(request);
  }

  /// 完成一次定位：恢复播放或保存进度，并结束等待状态。
  void _completePendingSeek(_SeekRequest request) {
    if (!_isCurrentSeek(request)) return;
    _endPendingSeek();
    _notifyPlaybackState(immediate: true);
    final player = request.player;
    if (request.resumeAfter) {
      if (player != null) unawaited(_runCommand(player.play));
    } else {
      unawaited(_saveProgress());
    }
  }

  /// 同一播放器只保留一个在途定位命令，排队期间的中间目标直接由最新目标取代。
  void _dispatchLatestSeek() {
    if (_dispatchingSeek != null) return;
    final request = _seekRequest;
    final player = _commandPlayer;
    if (request == null || player == null || request.dispatched) return;
    _dispatchingSeek = request;
    unawaited(_dispatchSeek(request, player));
  }

  Future<void> _dispatchSeek(_SeekRequest request, Player player) async {
    request.player = player;
    request.dispatched = true;
    try {
      await player.seek(request.target);
      if (!_isCurrentSeek(request)) return;
      request.commandAccepted = true;
      await _settleSeek(request, player);
    } on Object catch (error) {
      if (!_isCurrentSeek(request)) return;
      _endPendingSeek();
      _error = error.toString();
      _playing = false;
      _notifyPlaybackState(immediate: true);
    } finally {
      if (identical(_dispatchingSeek, request)) {
        _dispatchingSeek = null;
        _dispatchLatestSeek();
      }
    }
  }

  /// 所有定位入口的统一提交点：只保留最新目标，等待期间展示缓冲提示。
  void _requestSeek(Duration target, {required bool resumeAfter}) {
    if (_disposed) return;
    final clamped = _clampToDuration(target);
    final request = _SeekRequest(target: clamped, resumeAfter: resumeAfter);
    final player = _commandPlayer;
    if (player == null) {
      // 播放器未就绪：只记录用户最后选择的位置，初始化完成后补发一次。
      _seekRequest = _isInitializing ? request : null;
      _position = clamped;
      _refreshBuffering();
      _notifyPlaybackState(immediate: true);
      return;
    }
    _seekRequest = request;
    _position = clamped;
    // 等待定位落地期间保持缓冲提示，卡死由既有 bufferingTimeout 统一兜底。
    _refreshBuffering(armWatchdog: true);
    _notifyPlaybackState(immediate: true);
    _dispatchLatestSeek();
  }

  /// 捕获异步命令失败；仅忽略旧会话的回包，当前会话仍保留错误供重试。
  Future<void> _runCommand(Future<void> Function() command) async {
    final player = _commandPlayer;
    final generation = _initializationGeneration;
    if (player == null) return;
    try {
      await command();
    } on Object catch (error) {
      if (_disposed ||
          generation != _initializationGeneration ||
          !identical(player, _player)) {
        return;
      }
      _endPendingSeek();
      _error = error.toString();
      _playing = false;
      _notifyPlaybackState(immediate: true);
    }
  }

  Duration _clampToDuration(Duration value) {
    final total = duration.inMilliseconds;
    if (total <= 0) return value < Duration.zero ? Duration.zero : value;
    return Duration(milliseconds: value.inMilliseconds.clamp(0, total));
  }

  static Duration? _parseSeconds(String value) {
    final seconds = double.tryParse(value.trim());
    if (seconds == null || seconds.isNaN) return null;
    return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round(),
    );
  }

  void _onBufferingTimedOut() {
    if (_disposed) return;
    // 等待中的定位一并结束，错误提示后不留下会恢复播放的旧请求。
    _endPendingSeek();
    _error = '播放缓冲超时，请稍后重试';
    _playing = false;
    final player = _player;
    if (player != null) unawaited(_runCommand(player.pause));
    _notifyPlaybackState(immediate: true);
  }

  /// 测试注入初始化状态，复用生产 generation 与 watchdog 生命周期。
  @visibleForTesting
  void debugBeginInitialization() {
    if (_disposed) return;
    _invalidateInitializationGeneration();
    final generation = ++_initializationGeneration;
    _initialized = false;
    _initializationFailed = false;
    _buffering = false;
    _playing = false;
    _error = null;
    _armInitializationWatchdog(generation);
    notifyListeners();
  }

  /// 测试注入缓冲状态，不经过 media_kit。
  @visibleForTesting
  void debugSetBuffering(bool value) {
    // 没有初始化 watchdog 时允许单独验证再缓冲超时；生产事件只在已初始化后计时。
    _setBuffering(
      value,
      armWatchdog: !_initialized && _initializationWatchdog == null,
    );
    _notifyPlaybackState(immediate: true);
  }

  Future<void> _cancelPlayerSubscriptions() async {
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _playerSubscriptions,
    );
    _playerSubscriptions.clear();
    for (final subscription in subscriptions) {
      await _cancelSubscription(subscription);
    }
  }

  /// 同步底层播放位置；续播真正开始前忽略装载阶段的零值，避免覆盖待恢复进度。
  @visibleForTesting
  void syncPosition(Duration value) {
    final pending = _pendingResumePosition;
    if (pending != null) {
      if (value <= Duration.zero) return;
      _pendingResumePosition = null;
    }
    _position = value;
    _notifyPlaybackState();
  }

  /// 重新创建失败的视频解码器；地址仍不可用时更新错误但不离开播放器。
  Future<void> retry() async {
    if (_disposed) return;
    final session = _apiSession;
    final streamUrl = item.streamUrl;
    _invalidateInitializationGeneration();
    _initialized = false;
    _error = null;
    _initializationFailed = false;
    _playing = false;
    notifyListeners();
    if (item.status != 'ready') {
      _error = '媒体尚未就绪，当前状态：${item.status}';
      notifyListeners();
      return;
    }
    if (session == null || streamUrl == null || streamUrl.isEmpty) {
      _error = '服务端未返回可播放的视频流地址';
      notifyListeners();
      return;
    }
    await _initializeVideo(session, streamUrl);
  }

  /// 将当前媒体定位到零并继续播放；初始化尚未完成时改写本次起播位置。
  Future<void> restartFromBeginning() async {
    if (_disposed) return;
    _startAtZero = true;
    _pendingResumePosition = null;
    _position = Duration.zero;
    if (_commandPlayer == null) {
      _requestSeek(Duration.zero, resumeAfter: true);
      if (_initializationFailed) await retry();
      return;
    }
    _startAtZero = false;
    // 从头播放视为用户主动重试，定位失败时会重新写入错误。
    _error = null;
    _requestSeek(Duration.zero, resumeAfter: true);
  }

  void toggleControls() {
    if (_locked) {
      showLockHint();
      return;
    }
    _controlsVisible = !_controlsVisible;
    notifyListeners();
    if (_controlsVisible) {
      scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  /// 显示控制层并重新开始自动隐藏计时。
  void showControls() {
    if (_locked) {
      showLockHint();
      return;
    }
    if (!_controlsVisible) {
      _controlsVisible = true;
      notifyListeners();
    }
    scheduleHide();
  }

  /// 切换播放状态；显式暂停会取消定位结束后的自动续播，并保存当前进度。
  void togglePlay({bool revealControls = true}) {
    if (revealControls) {
      _controlsVisible = true;
      scheduleHide();
    }
    final player = _commandPlayer;
    if (player == null) {
      if (_position >= duration) _position = Duration.zero;
      _playing = !_playing;
      notifyListeners();
      return;
    }
    if (_position >= duration) {
      // 播放结束后再次操作：先回到开头，等待定位落地后再决定播放状态。
      _requestSeek(Duration.zero, resumeAfter: !_playing);
      if (_playing) unawaited(_runCommand(player.pause));
      return;
    }
    if (_playing) {
      // 用户显式暂停：等待中的定位不再自动恢复播放。
      _seekRequest?.resumeAfter = false;
      unawaited(_runCommand(player.pause));
      unawaited(_saveProgress());
    } else {
      unawaited(_runCommand(player.play));
    }
  }

  /// 相对当前显示位置快进或快退；等待原生定位结束时保留目标位置和缓冲提示。
  void seekBy(int seconds, {bool revealControls = true}) {
    // 连续快进只保留最后一次目标，旧请求的续作不会写回播放状态。
    _requestSeek(
      _position + Duration(seconds: seconds),
      resumeAfter: _playing || (_seekRequest?.resumeAfter ?? false),
    );
    if (revealControls) {
      _controlsVisible = true;
      scheduleHide();
    }
  }

  /// 开始拖动预览并暂时暂停播放；取代旧定位的续作，保留拖动前的播放意图。
  void beginScrub() {
    if (_scrubbing) return;
    _scrubbing = true;
    _scrubOrigin = _position;
    // 上一次拖动提交的定位可能还在等待恢复播放，按最新意图决定是否续播。
    final pending = _seekRequest;
    _resumeAfterScrub = _playing || (pending?.resumeAfter ?? false);
    // 拖动接管目标与播放状态后，旧定位请求不再续作，也不会在中途保存拖动位置。
    _scrubNativeMoved =
        _dispatchingSeek != null || (pending != null && pending.dispatched);
    _endPendingSeek();
    if (_resumeAfterScrub) {
      final player = _commandPlayer;
      if (player != null) unawaited(_runCommand(player.pause));
    }
    pauseAutoHide();
  }

  /// 更新拖动预览，不向解码器发送中间位置；提交时才定位。
  void updateScrub(Duration target) {
    if (!_scrubbing) beginScrub();
    _position = Duration(
      milliseconds: target.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    notifyListeners();
  }

  /// 提交最终拖动位置；原生定位结束后按拖动前的状态续播或保存暂停进度。
  void commitScrub() {
    if (!_scrubbing) return;
    final target = _position;
    final shouldResume = _resumeAfterScrub;
    final hasPlayer = _commandPlayer != null;
    _finishScrub();
    _requestSeek(target, resumeAfter: shouldResume);
    if (!hasPlayer && !shouldResume) {
      // 播放器未就绪时同样要保存暂停状态下的拖动位置。
      unawaited(_saveProgress());
    }
    notifyListeners();
  }

  /// 取消拖动并恢复起点；此前定位已下发时先让底层回到起点再续播。
  void cancelScrub() {
    if (!_scrubbing) return;
    final origin = _scrubOrigin ?? _position;
    final shouldResume = _resumeAfterScrub;
    final nativeMoved = _scrubNativeMoved;
    _position = origin;
    _finishScrub();
    final player = _commandPlayer;
    if (player != null) {
      if (nativeMoved) {
        // 上一次提交已让底层跳到别处，取消时用同一条链路回到拖动起点。
        _requestSeek(origin, resumeAfter: shouldResume);
      } else if (shouldResume) {
        unawaited(_runCommand(player.play));
      }
    }
    notifyListeners();
  }

  void _finishScrub() {
    _scrubbing = false;
    _scrubOrigin = null;
    _resumeAfterScrub = false;
    _scrubNativeMoved = false;
    scheduleHide();
  }

  void setPlaybackSpeed(double value, {bool revealControls = true}) {
    _speed = value;
    final player = _commandPlayer;
    if (player != null) unawaited(_runCommand(() => player.setRate(value)));
    if (revealControls) _controlsVisible = true;
    notifyListeners();
    if (revealControls) scheduleHide();
  }

  void setSpeed(double value) => setPlaybackSpeed(value);

  /// 设置播放器内部音量并同步静音状态；值会限制在 0 到 1。
  void setLocalVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    if (next > 0) {
      _volumeBeforeMute = next;
      _muted = false;
    } else {
      if (_volume > 0) _volumeBeforeMute = _volume;
      _muted = true;
    }
    _volume = next;
    final player = _commandPlayer;
    if (player != null) {
      unawaited(_runCommand(() => player.setVolume(next * 100)));
    }
    notifyListeners();
  }

  /// 在静音与上次非零音量之间切换。
  void toggleMute() {
    if (_muted || _volume <= 0.001) {
      setLocalVolume(_volumeBeforeMute.clamp(0.05, 1.0));
    } else {
      setLocalVolume(0);
    }
  }

  void setLocked(bool value) {
    _lockHintTimer?.cancel();
    _locked = value;
    _controlsVisible = true;
    notifyListeners();
    if (value) {
      _lockHintTimer = Timer(const Duration(seconds: 2), () {
        if (_disposed || !_locked) return;
        _controlsVisible = false;
        notifyListeners();
      });
    } else {
      scheduleHide();
    }
  }

  void showLockHint() {
    if (!_locked) return;
    _lockHintTimer?.cancel();
    _controlsVisible = true;
    notifyListeners();
    _lockHintTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed || !_locked) return;
      _controlsVisible = false;
      notifyListeners();
    });
  }

  void scheduleHide() {
    _hideTimer?.cancel();
    if (_locked) return;
    _hideTimer = Timer(autoHideDelay, () {
      _hideTimer = null;
      _controlsVisible = false;
      notifyListeners();
    });
  }

  void pauseAutoHide() => _hideTimer?.cancel();

  Future<void> _saveProgress({bool forceEnd = false}) async {
    if (_initializationFailed) return;
    final total = duration.inMilliseconds;
    if (total <= 0 && !forceEnd) return;
    final positionMs = forceEnd && total > 0
        ? total
        : _position.inMilliseconds.clamp(0, total > 0 ? total : 1 << 30);
    try {
      await _media.updateProgress(item.id, positionMs);
    } on Object {
      // 后续的定时或生命周期保存会使用最新进度重试。
    }
  }

  Future<void> persistProgress() => _saveProgress();

  Future<void> shutdown() async {
    if (_disposed) return;
    final position = _position;
    // 先释放解码器和音频，再做 best-effort 网络同步，离开页面不会继续播放。
    dispose();
    try {
      await _media
          .updateProgress(item.id, position.inMilliseconds)
          .timeout(const Duration(seconds: 2));
    } on Object {
      // 退出播放不能因进度同步失败而被阻塞。
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _initializationGeneration++;
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _syncThrottle?.cancel();
    _lockHintTimer?.cancel();
    _initializationWatchdog?.cancel();
    _initializationWatchdog = null;
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
    _resetSeekState();
    _mediaRequestRouter.revoke(_mediaRouteToken);
    _mediaRouteToken = null;
    final player = _player;
    _player = null;
    _videoController = null;
    _detachPlayerSubscriptions();
    if (player != null) unawaited(_disposePlayer(player));
    super.dispose();
  }
}

/// 一次定位请求；只有仍是控制器当前请求的对象才允许续作或收束。
class _SeekRequest {
  _SeekRequest({required this.target, required this.resumeAfter});

  /// 用户最后要求到达的位置。
  final Duration target;

  /// 定位结束后是否恢复播放；用户暂停会改写它。
  bool resumeAfter;

  /// 实际收到命令的播放器；初始化期间为 null，起播后补发。
  Player? player;

  /// 是否已下发命令；此时才允许把原生事件归到本次定位。
  bool dispatched = false;

  /// 命令是否已被原生接受；这是采用原生状态判定的前提。
  bool commandAccepted = false;
}
