import 'package:flutter/material.dart';

import '../../core/theme.dart';

class LumaFavoriteButton extends StatelessWidget {
  const LumaFavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onPressed,
    this.overlay = false,
    this.tooltip,
  });

  final bool isFavorite;
  final VoidCallback? onPressed;
  final bool overlay;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final label = tooltip ?? (isFavorite ? '取消收藏' : '收藏');
    final heartColor = Theme.of(context).colorScheme.error;
    final icon = AnimatedSwitcher(
      duration: LumaMotion.forContext(context, LumaMotion.fast),
      switchInCurve: LumaMotion.standard,
      switchOutCurve: LumaMotion.standard,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Icon(
        key: ValueKey(isFavorite),
        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: LumaIconSize.inline,
        color: overlay ? heartColor : null,
        // 不使用底板仍需与复杂封面分离，细投影只贴合图标轮廓。
        shadows: overlay
            ? [
                Shadow(
                  color: LumaColors.ink.withAlpha(190),
                  offset: const Offset(0, 1),
                  blurRadius: 2,
                ),
              ]
            : null,
      ),
    );

    if (overlay) {
      return IconButton(
        tooltip: label,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: heartColor,
          overlayColor: heartColor.withAlpha(30),
          minimumSize: const Size(
            LumaLayout.minTapTarget,
            LumaLayout.minTapTarget,
          ),
          maximumSize: const Size(
            LumaLayout.minTapTarget,
            LumaLayout.minTapTarget,
          ),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.standard,
        ),
        icon: icon,
      );
    }

    return IconButton.filledTonal(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size(
          LumaLayout.minTapTarget,
          LumaLayout.minTapTarget,
        ),
        visualDensity: VisualDensity.standard,
      ),
      icon: icon,
    );
  }
}
