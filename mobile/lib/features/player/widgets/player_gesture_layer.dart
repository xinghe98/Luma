import 'package:flutter/material.dart';

import '../player_interaction_controller.dart';

class PlayerGestureLayer extends StatefulWidget {
  const PlayerGestureLayer({super.key, required this.interaction});

  final PlayerInteractionController interaction;

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
            onDoubleTap: () =>
                widget.interaction.handleDoubleTap(_doubleTapX, size.width),
            onPanStart: (details) =>
                widget.interaction.beginPan(details.localPosition, size),
            onPanUpdate: (details) =>
                widget.interaction.updatePan(details.delta),
            onPanEnd: (_) => widget.interaction.endPan(),
            onPanCancel: () => widget.interaction.endPan(cancelled: true),
            onLongPressStart: (_) => widget.interaction.beginLongPress(),
            onLongPressEnd: (_) => widget.interaction.endLongPress(),
          ),
        );
      },
    );
  }
}
