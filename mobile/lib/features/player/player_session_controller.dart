// 应用级播放会话，持有跨全屏播放器和悬浮小窗复用的解码器。
// 页面只负责展示和交互，关闭会话时才停止播放并释放资源。
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/api/api_session.dart';
import '../../data/models/media_item.dart';
import 'player_controller.dart';

class PlayerSessionController extends ChangeNotifier {
  /// 创建播放会话；媒体控制器和会话信息用于创建底层播放器。
  /// 播放器关闭并完成进度同步后，会通过回调标记关联作品需要刷新。
  PlayerSessionController({
    required MediaController media,
    required ApiSession apiSession,
    ValueChanged<String?>? onCatalogInvalidated,
  }) : _media = media,
       _apiSession = apiSession,
       _onCatalogInvalidated = onCatalogInvalidated;

  final MediaController _media;
  final ApiSession _apiSession;
  final ValueChanged<String?>? _onCatalogInvalidated;
  PlayerController? _player;
  bool _minimized = false;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// 当前播放控制器；没有活动会话时为 null。
  PlayerController? get player => _player;

  /// 小窗是否应显示在应用根层之上。
  bool get minimized => _minimized && _player != null;

  /// 以指定媒体启动或复用会话；同媒体从头播放会重置现有解码器位置。
  void start(MediaItem item, {bool startFromBeginning = false}) {
    final active = _player;
    if (active != null && active.item.id == item.id) {
      if (startFromBeginning) active.restartFromBeginning();
      // 已在全屏会话中则无需通知，避免 didChangeDependencies 期间 markNeedsBuild。
      if (!_minimized) return;
      _minimized = false;
      _notifySafely();
      return;
    }
    if (active != null) {
      _player = null;
      _minimized = false;
      _notifySafely();
      // 新媒体的启动不等待旧解码器的网络进度同步。
      _shutdownAndInvalidate(active);
    }
    final player = PlayerController(
      item: item,
      media: _media,
      apiSession: _apiSession,
      startFromBeginning: startFromBeginning,
    );
    _player = player;
    _minimized = false;
    player.start();
    _notifySafely();
  }

  /// 收起全屏界面并保留正在播放的会话。
  void minimize() {
    if (_player == null || _minimized) return;
    _minimized = true;
    _notifySafely();
  }

  /// 将小窗切回全屏展示，路由跳转由调用方执行。
  void expand() {
    if (!minimized) return;
    _minimized = false;
    _notifySafely();
  }

  /// 停止当前会话并保存进度；断开服务器时可跳过随后无意义的作品刷新。
  Future<void> close({bool invalidateCatalog = true}) async {
    final player = _player;
    if (player == null) return;
    _player = null;
    _minimized = false;
    _notifySafely();
    await player.shutdown();
    if (invalidateCatalog) {
      _onCatalogInvalidated?.call(player.item.catalogItemId);
    }
  }

  /// 保存旧播放器进度后标记关联作品过期，不阻塞新媒体起播。
  Future<void> _shutdownAndInvalidate(PlayerController player) async {
    await player.shutdown();
    if (!_disposed) _onCatalogInvalidated?.call(player.item.catalogItemId);
  }

  /// build 阶段合并为帧末一次通知，避免「setState during build」。
  /// 状态字段仍同步更新；仅 UI 订阅推迟，不会丢最终态。
  void _notifySafely() {
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!_disposed) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final player = _player;
    _player = null;
    _minimized = false;
    if (player != null) player.dispose();
    super.dispose();
  }
}
