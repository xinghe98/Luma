// 播放器的视频画面，供全屏场景与悬浮小窗复用同一个视频纹理。
// 同一时刻只允许一个宿主挂载 VideoPlayer，避免平台纹理被重复绑定后失效。
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../shared/media/media_artwork.dart';
import '../player_controller.dart';

class PlayerVideoSurface extends StatefulWidget {
  /// 显示已初始化的视频；[attachVideo] 为 false 时不挂载纹理，仅保留占位。
  const PlayerVideoSurface({
    super.key,
    required this.controller,
    this.attachVideo = true,
  });

  final PlayerController controller;

  /// 是否挂载 [VideoPlayer]。全屏与小窗切换时必须互斥为 true。
  final bool attachVideo;

  @override
  State<PlayerVideoSurface> createState() => _PlayerVideoSurfaceState();
}

class _PlayerVideoSurfaceState extends State<PlayerVideoSurface> {
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(covariant PlayerVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_sync);
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final initialized = widget.controller.initialized;
    final error = widget.controller.error;
    if (_initialized == initialized && _error == error) return;
    if (!mounted) return;
    setState(() {
      _initialized = initialized;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.controller.videoController;
    if (widget.attachVideo && _initialized && video != null) {
      final ratio = video.value.aspectRatio;
      if (ratio > 0) {
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio,
              child: VideoPlayer(video),
            ),
          ),
        );
      }
    }
    if (!widget.attachVideo) {
      return const ColoredBox(color: Colors.black);
    }
    return MediaArtwork(item: widget.controller.item, borderRadius: 0);
  }
}
