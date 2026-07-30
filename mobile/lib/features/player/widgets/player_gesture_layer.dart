import 'package:flutter/material.dart';

import '../player_interaction_controller.dart';

class PlayerGestureLayer extends StatefulWidget {
  /// 创建播放器交互层；桌面双击交给窗口全屏，触控端保留分区手势。
  const PlayerGestureLayer({
    super.key,
    required this.interaction,
    this.desktop = false,
    this.onDesktopDoubleTap,
  });

  final PlayerInteractionController interaction;
  final bool desktop;
  final VoidCallback? onDesktopDoubleTap;

  @override
  State<PlayerGestureLayer> createState() => _PlayerGestureLayerState();
}

class _PlayerGestureLayerState extends State<PlayerGestureLayer> {
  double _doubleTapX = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Semantics(
          label: '视频手势区域：单击显示控制，双击快退、播放或快进，横滑进度，左右竖滑调节亮度和音量',
          container: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.interaction.handleTap,
            onDoubleTapDown: (details) {
              _doubleTapX = details.localPosition.dx;
            },
            onDoubleTap: widget.desktop
                ? widget.onDesktopDoubleTap
                : () => widget.interaction.handleDoubleTap(
                    _doubleTapX,
                    size.width,
                  ),
            onPanStart: widget.desktop
                ? null
                : (details) =>
                      widget.interaction.beginPan(details.localPosition, size),
            onPanUpdate: widget.desktop
                ? null
                : (details) => widget.interaction.updatePan(details.delta),
            onPanEnd: widget.desktop
                ? null
                : (_) => widget.interaction.endPan(),
            onPanCancel: widget.desktop
                ? null
                : () => widget.interaction.endPan(cancelled: true),
            onLongPressStart: widget.desktop
                ? null
                : (_) => widget.interaction.beginLongPress(),
            onLongPressEnd: widget.desktop
                ? null
                : (_) => widget.interaction.endLongPress(),
          ),
        );
      },
    );
  }
}
