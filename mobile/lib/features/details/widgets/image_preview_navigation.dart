// 图片预览的画廊导航区：上一张/下一张按钮、序号与远端分页状态。
// 由 ImagePreviewDialog 持有；只读取 ImageGalleryController 的公开状态，不负责其生命周期。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/media/image_gallery_controller.dart';

/// 画廊导航条：居中显示「第 N 张」序号与加载、错误状态，
/// 两端为不小于 48dp 的上一张/下一张按钮；远端还有分页时下一张保持可用。
/// 普通端与 TV 复用同一区域，TV 通过 [television] 放大为可聚焦的遥控器动作。
class ImagePreviewNavigationBar extends StatelessWidget {
  /// 显示切图与分页状态；加载期间暂停切图，控制器由预览调用方释放。
  const ImagePreviewNavigationBar({
    super.key,
    required this.gallery,
    this.television = false,
    this.previousFocusNode,
    this.nextFocusNode,
  });

  final ImageGalleryController gallery;

  /// TV：使用带文字的大号动作按钮；普通端使用 48dp 图标按钮。
  final bool television;

  /// TV：两个方向按钮的焦点节点，供工具栏与图片区安排焦点顺序。
  final FocusNode? previousFocusNode;
  final FocusNode? nextFocusNode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: gallery,
      builder: (context, _) {
        final extras = context.luma;
        final children = <Widget>[
          _NavButton(
            television: television,
            focusNode: previousFocusNode,
            tooltip: '上一张',
            icon: Icons.chevron_left_rounded,
            onPressed: gallery.canPrevious && !gallery.isLoadingMore
                ? gallery.previous
                : null,
          ),
          const SizedBox(width: LumaSpacing.xs),
          Flexible(
            child: _NavStatus(gallery: gallery, extras: extras),
          ),
          const SizedBox(width: LumaSpacing.xs),
          _NavButton(
            television: television,
            focusNode: nextFocusNode,
            tooltip: '下一张',
            icon: Icons.chevron_right_rounded,
            onPressed: gallery.canNext && !gallery.isLoadingMore
                ? () => unawaited(gallery.next())
                : null,
          ),
        ];
        final content = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: children,
        );
        if (television) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: extras.badgeScrim,
              borderRadius: BorderRadius.circular(LumaRadii.medium),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LumaSpacing.xs,
                vertical: LumaSpacing.xxs,
              ),
              child: content,
            ),
          );
        }
        // 底部遮罩渐变沿用暗色 viewer 令牌，保证浅色图片上序号与按钮可读。
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LumaGradients.bottomScrim(extras.playerInk),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                LumaSpacing.xs,
                LumaSpacing.xl,
                LumaSpacing.xs,
                LumaSpacing.xs,
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

/// 序号与远端分页状态：加载中不打断浏览，失败保留当前图并提示重试。
class _NavStatus extends StatelessWidget {
  const _NavStatus({required this.gallery, required this.extras});

  final ImageGalleryController gallery;
  final LumaExtras extras;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = gallery.isLoadingMore
        ? '正在加载更多…'
        : (gallery.error != null ? '加载失败，点下一张重试' : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // 只报当前序号：length 是已加载子集，不能当成全库总数。
          '第 ${gallery.currentIndex + 1} 张',
          style: theme.textTheme.titleSmall?.copyWith(
            color: extras.onPlayerInk,
          ),
        ),
        if (status != null) ...[
          const SizedBox(height: LumaSpacing.xxs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (gallery.isLoadingMore)
                Padding(
                  padding: const EdgeInsets.only(right: LumaSpacing.xxs),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: extras.onPlayerInkMuted,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: LumaSpacing.xxs),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                ),
              Flexible(
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: gallery.error != null
                        ? theme.colorScheme.error
                        : extras.onPlayerInkMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.television,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.focusNode,
  });

  final bool television;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final extras = context.luma;
    if (television) {
      // TV 沿用工具栏的文字按钮形态，遥控器可聚焦。
      return Tooltip(
        message: tooltip,
        child: TextButton.icon(
          focusNode: focusNode,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, LumaTvLayout.controlMinHeight),
            foregroundColor: extras.onPlayerInk,
          ),
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(tooltip),
        ),
      );
    }
    return IconButton.filledTonal(
      tooltip: tooltip,
      focusNode: focusNode,
      style: IconButton.styleFrom(
        backgroundColor: extras.badgeScrim,
        foregroundColor: extras.onPlayerInk,
        minimumSize: const Size(48, 48),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
