// 播放控制器封装视频解码、播放状态、交互状态与进度持久化。
// 初始化和重试使用 generation 丢弃旧回包，销毁后不再更新任何可见状态。
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
  bool _startAtZero;
  Duration? _pendingResumePosition;
  late Duration _position;
  Timer? _hideTimer;
  Timer? _saveTimer;
  Timer? _syncThrottle;
  Timer? _lockHintTimer;
  Timer? _bufferingWatchdog;
  Player? _player;
  VideoController? _videoController;
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
    final access = session.resolveResource(streamUrl);
    _mediaRequestRouter.revoke(_mediaRouteToken);
    _mediaRouteToken = null;
    final previous = _player;
    _player = null;
    _videoController = null;
    _initialized = false;
    await _cancelPlayerSubscriptions();
    if (previous != null) await previous.dispose();
    if (_disposed || generation != _initializationGeneration) return;

    final player = Player(
      configuration: const PlayerConfiguration(
        title: '轻影',
        bufferSize: 128 * 1024 * 1024,
      ),
    );
    _player = player;
    _videoController = VideoController(player);
    _listenToPlayer(player, generation);
    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('network-timeout', '60');
        await platform.setProperty('force-seekable', 'yes');
        await platform.setProperty('demuxer-readahead-secs', '20');
      }
      if (_disposed || generation != _initializationGeneration) {
        await player.dispose();
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
        await player.dispose();
        return;
      }
      await player.setVolume(_volume * 100);
      await player.play();
      if (_disposed || generation != _initializationGeneration) return;
      _startAtZero = false;
      _initialized = true;
      _initializationFailed = false;
      _error = null;
      _playing = true;
      notifyListeners();
    } on Object catch (error) {
      if (_disposed || generation != _initializationGeneration) return;
      _initializationFailed = true;
      _error = error.toString();
      _playing = false;
      notifyListeners();
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
        syncPosition(value);
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
            !completed) {
          return;
        }
        _position = duration;
        unawaited(_saveProgress(forceEnd: true));
        _notifyPlaybackState(immediate: true);
      }),
      player.stream.error.listen((message) {
        if (_disposed || generation != _initializationGeneration) return;
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

  void _setBuffering(bool value) {
    _buffering = value;
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
    if (value) {
      final generation = _initializationGeneration;
      _bufferingWatchdog = Timer(bufferingTimeout, () {
        if (_disposed || generation != _initializationGeneration) return;
        _onBufferingTimedOut();
      });
    }
  }

  void _onBufferingTimedOut() {
    if (_disposed) return;
    _error = '播放缓冲超时，请稍后重试';
    _playing = false;
    unawaited(_player?.pause());
    _notifyPlaybackState(immediate: true);
  }

  /// 测试注入缓冲状态，不经过 media_kit。
  @visibleForTesting
  void debugSetBuffering(bool value) {
    _setBuffering(value);
    _notifyPlaybackState(immediate: true);
  }

  Future<void> _cancelPlayerSubscriptions() async {
    final subscriptions = List<StreamSubscription<dynamic>>.from(
      _playerSubscriptions,
    );
    _playerSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
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
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
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
    final player = _player;
    if (player == null || !initialized) {
      notifyListeners();
      if (_initializationFailed) await retry();
      return;
    }
    try {
      await player.seek(Duration.zero);
      if (_disposed) return;
      await player.play();
      if (_disposed) return;
      _startAtZero = false;
      _playing = true;
      _error = null;
      notifyListeners();
    } on Object catch (error) {
      if (_disposed) return;
      _error = error.toString();
      notifyListeners();
    }
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

  void togglePlay({bool revealControls = true}) {
    final player = _player;
    if (player != null && initialized) {
      if (_position >= duration) {
        unawaited(player.seek(Duration.zero));
      }
      if (_playing) {
        unawaited(player.pause());
        unawaited(_saveProgress());
      } else {
        unawaited(player.play());
      }
      if (revealControls) {
        _controlsVisible = true;
        scheduleHide();
      }
      return;
    }
    if (_position >= duration) _position = Duration.zero;
    _playing = !_playing;
    if (revealControls) _controlsVisible = true;
    notifyListeners();
    if (revealControls) scheduleHide();
  }

  void seekBy(int seconds, {bool revealControls = true}) {
    final target = _position + Duration(seconds: seconds);
    _position = Duration(
      milliseconds: target.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    if (initialized) unawaited(_player!.seek(_position));
    if (revealControls) _controlsVisible = true;
    notifyListeners();
    if (revealControls) scheduleHide();
  }

  void beginScrub() {
    if (_scrubbing) return;
    _scrubbing = true;
    _scrubOrigin = _position;
    _resumeAfterScrub = _playing;
    if (_resumeAfterScrub && initialized) unawaited(_player!.pause());
    pauseAutoHide();
  }

  void updateScrub(Duration target) {
    if (!_scrubbing) beginScrub();
    _position = Duration(
      milliseconds: target.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    notifyListeners();
  }

  void commitScrub() {
    if (!_scrubbing) return;
    final target = _position;
    final shouldResume = _resumeAfterScrub;
    _finishScrub();
    if (initialized) {
      unawaited(_commitVideoScrub(target, shouldResume));
    } else if (!shouldResume) {
      // 未初始化播放器时同样要保存暂停状态下的拖动位置。
      unawaited(_saveProgress());
    }
    notifyListeners();
  }

  Future<void> _commitVideoScrub(Duration target, bool shouldResume) async {
    final player = _player;
    if (player == null) return;
    try {
      await player.seek(target);
      if (shouldResume && !_disposed) {
        await player.play();
      } else {
        await _saveProgress();
      }
    } on Object catch (error) {
      if (_disposed) return;
      _error = error.toString();
      notifyListeners();
    }
  }

  void cancelScrub() {
    if (!_scrubbing) return;
    final origin = _scrubOrigin ?? _position;
    final shouldResume = _resumeAfterScrub;
    _position = origin;
    _finishScrub();
    if (initialized && shouldResume) unawaited(_player!.play());
    notifyListeners();
  }

  void _finishScrub() {
    _scrubbing = false;
    _scrubOrigin = null;
    _resumeAfterScrub = false;
    scheduleHide();
  }

  void setPlaybackSpeed(double value, {bool revealControls = true}) {
    _speed = value;
    if (initialized) unawaited(_player!.setRate(value));
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
    if (initialized) unawaited(_player!.setVolume(next * 100));
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
    _bufferingWatchdog?.cancel();
    _mediaRequestRouter.revoke(_mediaRouteToken);
    _mediaRouteToken = null;
    final player = _player;
    _player = null;
    _videoController = null;
    unawaited(_cancelPlayerSubscriptions());
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }
}
