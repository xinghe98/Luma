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
                Positioned(
                  top: LumaSpacing.xxs,
                  right: LumaSpacing.xxs,
                  child: IconButton(
                    color: Colors.white,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                Positioned(
                  left: LumaSpacing.xxs,
                  bottom: LumaSpacing.xxs,
                  child: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) => IconButton.filledTonal(
                      onPressed: widget.controller.togglePlay,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(40),
                        backgroundColor: colors.surface.withValues(alpha: 0.9),
                        foregroundColor: colors.onSurface,
                      ),
                      icon: AnimatedSwitcher(
                        duration: duration,
                        child: Icon(
                          widget.controller.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey(widget.controller.playing),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LumaSpacing.xxl,
                    ),
                    child: Semantics(
                      button: true,
                      label: '还原全屏播放器',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onExpand,
                      ),
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
