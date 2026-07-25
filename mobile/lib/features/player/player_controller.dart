import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/api/api_session.dart';
import '../../data/models/media_item.dart';

class PlayerController extends ChangeNotifier {
  /// 创建播放控制器；startFromBeginning 为 true 时不读取既有进度。
  PlayerController({
    required this.item,
    required MediaController media,
    ApiSession? apiSession,
    this.startFromBeginning = false,
    this.autoHideDelay = const Duration(seconds: 4),
  }) : _media = media,
       _apiSession = apiSession,
       _position = startFromBeginning ? Duration.zero : item.duration * item.progress;

  final MediaItem item;
  final MediaController _media;
  final ApiSession? _apiSession;
  final bool startFromBeginning;
  final Duration autoHideDelay;
  late Duration _position;
  Timer? _hideTimer;
  Timer? _saveTimer;
  Timer? _syncThrottle;
  Timer? _lockHintTimer;
  VideoPlayerController? _videoController;
  String? _error;
  bool _disposed = false;
  bool _playing = false;
  bool _controlsVisible = true;
  bool _locked = false;
  bool _completedSaved = false;
  bool _initializationFailed = false;
  bool _scrubbing = false;
  bool _resumeAfterScrub = false;
  Duration? _scrubOrigin;
  double _speed = 1;

  Duration get position => _position;
  bool get playing => _playing;
  bool get controlsVisible => _controlsVisible;
  bool get locked => _locked;
  double get speed => _speed;
  bool get initialized => _videoController?.value.isInitialized ?? false;
  bool get buffering => _videoController?.value.isBuffering ?? false;
  bool get scrubbing => _scrubbing;
  String? get error => _error;
  VideoPlayerController? get videoController => _videoController;
  Duration get duration =>
      initialized ? _videoController!.value.duration : item.duration;

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
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(session.resolve(streamUrl)),
      httpHeaders: session.authorizationHeaders,
    );
    _videoController = controller;
    controller.addListener(_syncVideoState);
    try {
      await controller.initialize();
      if (_disposed) return;
      final initial = startFromBeginning
          ? Duration.zero
          : controller.value.duration * item.progress;
      if (initial > Duration.zero) await controller.seekTo(initial);
      await controller.play();
      _playing = true;
      notifyListeners();
    } on Object catch (error) {
      if (_disposed) return;
      _initializationFailed = true;
      _error = error.toString();
      _playing = false;
      notifyListeners();
    }
  }

  void _syncVideoState() {
    if (_disposed) return;
    final value = _videoController?.value;
    if (value == null) return;
    final wasPlaying = _playing;
    final previousError = _error;
    // 初始化失败时插件会回调一个 position=0 的 value，不能覆盖续播位置。
    if (!_scrubbing && value.isInitialized) _position = value.position;
    _playing = value.isPlaying;
    if (value.hasError) _error = value.errorDescription;
    final important = wasPlaying != _playing || previousError != _error;
    if (important) {
      _syncThrottle?.cancel();
      _syncThrottle = null;
      notifyListeners();
    } else {
      _syncThrottle ??= Timer(const Duration(milliseconds: 200), () {
        _syncThrottle = null;
        if (!_disposed) notifyListeners();
      });
    }
    _maybeSaveCompletion(value);
  }

  void _maybeSaveCompletion(VideoPlayerValue value) {
    if (!value.isInitialized || _completedSaved) return;
    final total = value.duration.inMilliseconds;
    if (total <= 0) return;
    final remaining = total - value.position.inMilliseconds;
    if (remaining <= 500 || (!value.isPlaying && remaining <= 1000)) {
      _completedSaved = true;
      unawaited(_saveProgress(forceEnd: true));
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

  void togglePlay({bool revealControls = true}) {
    final video = _videoController;
    if (video != null && video.value.isInitialized) {
      if (video.value.position >= video.value.duration) {
        _completedSaved = false;
        unawaited(video.seekTo(Duration.zero));
      }
      if (video.value.isPlaying) {
        unawaited(video.pause());
        unawaited(_saveProgress());
      } else {
        unawaited(video.play());
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
    if (initialized) unawaited(_videoController!.seekTo(_position));
    if (revealControls) _controlsVisible = true;
    notifyListeners();
    if (revealControls) scheduleHide();
  }

  void beginScrub() {
    if (_scrubbing) return;
    _scrubbing = true;
    _scrubOrigin = _position;
    _resumeAfterScrub = _playing;
    if (_resumeAfterScrub && initialized) unawaited(_videoController!.pause());
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
    final video = _videoController;
    if (video == null) return;
    try {
      await video.seekTo(target);
      if (shouldResume && !_disposed) {
        await video.play();
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
    if (initialized && shouldResume) unawaited(_videoController!.play());
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
    if (initialized) unawaited(_videoController!.setPlaybackSpeed(value));
    if (revealControls) _controlsVisible = true;
    notifyListeners();
    if (revealControls) scheduleHide();
  }

  void setSpeed(double value) => setPlaybackSpeed(value);

  void setLocalVolume(double value) {
    if (initialized) unawaited(_videoController!.setVolume(value.clamp(0, 1)));
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
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _syncThrottle?.cancel();
    _lockHintTimer?.cancel();
    final video = _videoController;
    _videoController = null;
    if (video != null) {
      video.removeListener(_syncVideoState);
      unawaited(video.dispose());
    }
    super.dispose();
  }
}
