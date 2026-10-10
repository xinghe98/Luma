// 播放器控制层的统一图标按钮：普通款 48dp 圆角方形、深色半透明底；
// prominent 款 64dp 反色主按钮（播放/暂停）。替换原先三套分散实现，
// 保证所有播放控制按钮的触控目标一致不小于 48dp。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 播放器控制层图标按钮。
/// [prominent] 为 true 时使用反色大按钮（如中央的播放键）；
/// [iconSize] 可覆盖默认图标尺寸，例如小窗内保持 22 但点击区域仍为 48。
class PlayerControlButton extends StatelessWidget {
  /// 构建播放器控制按钮；[onPressed] 为 null 时按禁用态展示。
  const PlayerControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.prominent = false,
    this.iconSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 是否使用 64dp 反色主按钮样式。
  final bool prominent;

  /// 图标尺寸；默认普通款 24、prominent 款 36。
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    final size = prominent ? 64.0 : 48.0;
    final resolvedIconSize = iconSize ?? (prominent ? 36.0 : 24.0);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: Size.square(size),
        backgroundColor: prominent
            ? extras.onPlayerInk
            : extras.playerInk.withValues(alpha: 0.55),
        foregroundColor: prominent ? extras.playerInk : extras.onPlayerInk,
        disabledForegroundColor: extras.onPlayerInk.withValues(
          alpha: LumaOpacity.disabled,
        ),
        shape: prominent
            ? const CircleBorder()
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(LumaRadii.small),
              ),
      ),
      icon: Icon(icon, size: resolvedIconSize),
    );
  }
}
