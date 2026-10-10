// 封面底部的已看进度条：海报、视频卡和继续观看大卡共用同一视觉。
// 纯展示组件，不持有状态；进度为 0 时由调用方决定是否挂载。
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 贴在封面底边的已看进度条。
///
/// 底部垫一层墨色渐变，再画半透明轨道和琥珀色已看部分，保证在浅色与深色
/// 封面上都能一眼看出进度；[height] 为进度条本身高度，渐变向上额外延伸。
class CoverProgressBar extends StatelessWidget {
  const CoverProgressBar({
    super.key,
    required this.progress,
    this.height = _defaultHeight,
  });

  /// 已看比例，超出 0–1 的值会被截断。
  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    // 进度条压在墨色渐变上，与主题亮暗无关，固定用深色主题的琥珀保证对比。
    const amber = LumaColors.darkPrimary;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              LumaColors.playerInk.withValues(alpha: 0.55),
              LumaColors.playerInk.withValues(alpha: 0),
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: height * 3),
          child: SizedBox(
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: LumaColors.onPlayerInk.withValues(alpha: 0.32),
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: const ColoredBox(color: amber),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _defaultHeight = 4.0;
