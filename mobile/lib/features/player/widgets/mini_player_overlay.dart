// 应用内悬浮小窗，复用当前播放会话并提供拖动、播放、关闭和还原入口。
// 挂在 MaterialApp.builder 根 Stack 最上层，盖过路由页与图片预览等 Dialog。
// 不依赖 Navigator Overlay（根层无 Overlay），避免 Tooltip/InkWell 报错。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';
import '../player_session_controller.dart';
import 'player_video_surface.dart';

class MiniPlayerOverlay extends StatelessWidget {
  /// 根据会话状态显示小窗，并由调用方负责打开对应的全屏路由。
  const MiniPlayerOverlay({
    super.key,
    required this.session,
    required this.onExpand,
    this.interactive = true,
  });

  final PlayerSessionController session;
  final ValueChanged<String> onExpand;
  final bool interactive;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final player = session.player;
      if (!session.minimized || player == null) return const SizedBox.shrink();
      final card = _MiniPlayerCard(
        controller: player,
        onClose: () => unawaited(session.close()),
        onExpand: () {
          // 先卸小窗纹理并隐藏，再推全屏页挂载，避免双绑定。
          session.expand();
          onExpand(player.item.id);
        },
      );
      return interactive ? card : IgnorePointer(child: card);
    },
  );
}

class _MiniPlayerCard extends StatefulWidget {
  const _MiniPlayerCard({
    required this.controller,
    required this.onClose,
    required this.onExpand,
  });

  final PlayerController controller;
  final VoidCallback onClose;
  final VoidCallback onExpand;

  @override
  State<_MiniPlayerCard> createState() => _MiniPlayerCardState();
}

class _MiniPlayerCardState extends State<_MiniPlayerCard> {
  Offset _dragOffset = Offset.zero;
  double _scale = 1;
  double _scaleAtStart = 1;
  Offset? _doubleTapPosition;
  String? _feedback;
  Timer? _feedbackTimer;

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  /// 按小窗宽度把双击分成快退、播放暂停和快进三个区域。
  void _handleDoubleTap(double width) {
    final x = _doubleTapPosition?.dx ?? width / 2;
    if (x < width / 3) {
      _seekBy(-10);
    } else if (x > width * 2 / 3) {
      _seekBy(10);
    } else {
      _togglePlay();
    }
  }

  /// 调整当前播放位置，并显示不会遮挡画面太久的操作反馈。
  void _seekBy(int seconds) {
    widget.controller.seekBy(seconds, revealControls: false);
    _showFeedback(seconds < 0 ? '快退 10 秒' : '快进 10 秒');
  }

  /// 切换播放状态，并用当前动作而非结果图标说明反馈。
  void _togglePlay() {
    final wasPlaying = widget.controller.playing;
    widget.controller.togglePlay();
    _showFeedback(wasPlaying ? '已暂停' : '继续播放');
  }

  void _showFeedback(String message) {
    _feedbackTimer?.cancel();
    setState(() => _feedback = message);
    _feedbackTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final baseWidth = (mediaQuery.size.width - LumaSpacing.lg * 2)
        .clamp(160.0, 280.0)
        .toDouble();
    final compactWidth = baseWidth < 220 ? baseWidth : 220.0;
    final maxScale = (mediaQuery.size.width - LumaSpacing.md) / compactWidth;
    final scale = _scale.clamp(0.8, maxScale.clamp(1.0, 1.7)).toDouble();
    final width = compactWidth * scale;
    final height = width / 1.6;
    final safeBottom =
        mediaQuery.padding.bottom + LumaLayout.navigationBarHeight;
    final base = Offset(
      mediaQuery.size.width - width - LumaSpacing.md,
      mediaQuery.size.height - height - safeBottom - LumaSpacing.md,
    );
    final position = _clampPosition(
      base + _dragOffset,
      mediaQuery.size,
      Size(width, height),
    );
    final colors = Theme.of(context).colorScheme;
    final duration = LumaMotion.forContext(context, LumaMotion.normal);
    return Positioned(
      key: const ValueKey('mini-player-card'),
      left: position.dx,
      top: position.dy,
      width: width,
      height: height,
      child: Semantics(
        container: true,
        label: '正在小窗播放：${widget.controller.item.title}',
        hint: '单击还原全屏，双击左侧快退、中间播放暂停、右侧快进',
        child: Material(
          color: colors.surfaceContainerHighest,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(LumaRadii.medium),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            onScaleStart: (_) => _scaleAtStart = _scale,
            onScaleUpdate: (details) => setState(() {
              _dragOffset += details.focalPointDelta;
              _scale = (_scaleAtStart * details.scale)
                  .clamp(0.8, maxScale.clamp(1.0, 1.7))
                  .toDouble();
            }),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 小窗可见时独占纹理；全屏页在 minimize 前会先卸下 VideoPlayer。
                PlayerVideoSurface(
                  controller: widget.controller,
                  attachVideo: true,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x5C000000),
                        Color(0x00000000),
                        Color(0x85000000),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Semantics(
                    button: true,
                    label: '还原全屏播放器',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onExpand,
                      onDoubleTapDown: (details) =>
                          _doubleTapPosition = details.localPosition,
                      onDoubleTap: () => _handleDoubleTap(width),
                    ),
                  ),
                ),
                Center(
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: LumaMotion.forContext(context, LumaMotion.fast),
                      child: _feedback == null
                          ? const SizedBox.shrink(
                              key: ValueKey('mini-player-feedback-empty'),
                            )
                          : Semantics(
                              key: ValueKey(_feedback),
                              liveRegion: true,
                              label: _feedback,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.surface.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(
                                    LumaRadii.small,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: LumaSpacing.sm,
                                    vertical: LumaSpacing.xs,
                                  ),
                                  child: Text(
                                    _feedback!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: colors.onSurface),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                Positioned(
                  top: LumaSpacing.xxs,
                  left: LumaSpacing.xxs,
                  child: _MiniPlayerIconButton(
                    label: '还原全屏播放器',
                    icon: Icons.fullscreen_rounded,
                    onPressed: widget.onExpand,
                  ),
                ),
                Positioned(
                  top: LumaSpacing.xxs,
                  right: LumaSpacing.xxs,
                  child: _MiniPlayerIconButton(
                    label: '关闭小窗播放器',
                    icon: Icons.close_rounded,
                    onPressed: widget.onClose,
                  ),
                ),
                Positioned(
                  left: LumaSpacing.xxs,
                  right: LumaSpacing.xxs,
                  bottom: LumaSpacing.xxs,
                  child: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _MiniPlayerIconButton(
                          label: '快退 10 秒',
                          icon: Icons.replay_10_rounded,
                          onPressed: () => _seekBy(-10),
                        ),
                        _MiniPlayerIconButton(
                          label: widget.controller.playing ? '暂停' : '播放',
                          icon: widget.controller.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          onPressed: _togglePlay,
                          selected: true,
                          animationDuration: duration,
                        ),
                        _MiniPlayerIconButton(
                          label: '快进 10 秒',
                          icon: Icons.forward_10_rounded,
                          onPressed: () => _seekBy(10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Offset _clampPosition(Offset position, Size viewport, Size card) {
    final minX = LumaSpacing.xs;
    final minY = LumaSpacing.xs;
    final maxX = (viewport.width - card.width - LumaSpacing.xs)
        .clamp(minX, double.infinity)
        .toDouble();
    final maxY = (viewport.height - card.height - LumaSpacing.xs)
        .clamp(minY, double.infinity)
        .toDouble();
    return Offset(position.dx.clamp(minX, maxX), position.dy.clamp(minY, maxY));
  }
}

class _MiniPlayerIconButton extends StatelessWidget {
  const _MiniPlayerIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.animationDuration = Duration.zero,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;
  final Duration animationDuration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(LumaLayout.minTapTarget),
            backgroundColor: colors.surface.withValues(
              alpha: selected ? 0.94 : 0.82,
            ),
            foregroundColor: colors.onSurface,
          ),
          icon: AnimatedSwitcher(
            duration: animationDuration,
            child: Icon(icon, key: ValueKey(icon)),
          ),
        ),
      ),
    );
  }
}
