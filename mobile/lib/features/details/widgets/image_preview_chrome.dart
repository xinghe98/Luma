// 图片预览顶栏 chrome：详情/缩放/删除/关闭动作排，普通端与 TV 两种形态。
// 由 ImagePreviewDialog 组合；删除进行中通过 [deleteInProgress] 展示进度并禁用入口。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 预览顶栏：普通端为顶部渐变一排图标按钮，TV 为底部圆角工具条。
/// [onDelete] 为 null 时删除按钮禁用；[deleteInProgress] 用进度圈占位保持宽度。
class ImagePreviewChrome extends StatelessWidget {
  const ImagePreviewChrome({
    super.key,
    required this.onDetails,
    required this.onClose,
    this.onDelete,
    this.deleteInProgress = false,
    this.deleteError,
    this.television = false,
    this.zoomIn,
    this.zoomOut,
    this.onReset,
    this.toolbarFocusNode,
  });

  final VoidCallback? onDetails;
  final VoidCallback? onClose;

  /// 删除入口；null 表示当前不可用（删除进行中或单图降级）。
  final VoidCallback? onDelete;

  /// 删除请求进行中：替换图标为进度指示，保持按钮宽度稳定。
  final bool deleteInProgress;

  /// 当前图片删除失败的原因，保留在预览内直到再次尝试。
  final String? deleteError;

  /// TV：放大/缩小/还原与详情、关闭都成为可见可聚焦动作，首按钮持焦点。
  final bool television;
  final VoidCallback? zoomIn;
  final VoidCallback? zoomOut;
  final VoidCallback? onReset;
  final FocusNode? toolbarFocusNode;

  @override
  Widget build(BuildContext context) {
    final error = deleteError;
    final controls = _controls(context);
    if (error == null) return controls;
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        controls,
        Material(
          color: colors.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(LumaSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Text('$error\n可再次点击删除重试。',
                style: TextStyle(color: colors.onErrorContainer)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    final extras = context.luma;
    var chromeStyle = IconButton.styleFrom(
      backgroundColor: extras.badgeScrim,
      foregroundColor: extras.onPlayerInk,
    );
    if (television) {
      // TV 控件最小 56dp，保证观看距离可点中。
      chromeStyle = chromeStyle.copyWith(
        minimumSize: const WidgetStatePropertyAll(
          Size(LumaTvLayout.controlMinHeight, LumaTvLayout.controlMinHeight),
        ),
      );
    }
    final theme = Theme.of(context);
    final detailsButton = IconButton.filledTonal(
      tooltip: '详情',
      style: chromeStyle,
      onPressed: onDetails,
      icon: const Icon(Icons.info_outline_rounded),
    );
    final closeButton = IconButton.filledTonal(
      tooltip: '关闭',
      style: chromeStyle,
      onPressed: onClose,
      icon: const Icon(Icons.close_rounded),
    );
    if (!television) {
      // 普通端顶栏：底部遮罩反转为顶部渐变，缩放与详情、关闭同一排。
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: LumaGradients.bottomScrim(extras.playerInk).colors,
            stops: LumaGradients.bottomScrim(extras.playerInk).stops,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LumaSpacing.xs,
              LumaSpacing.xs,
              LumaSpacing.xs,
              LumaSpacing.xl,
            ),
            child: Row(
              children: [
                detailsButton,
                const Spacer(),
                IconButton.filledTonal(
                  tooltip: '放大',
                  style: chromeStyle,
                  onPressed: zoomIn,
                  icon: const Icon(Icons.zoom_in_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: '缩小',
                  style: chromeStyle,
                  onPressed: zoomOut,
                  icon: const Icon(Icons.zoom_out_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: '还原',
                  style: chromeStyle,
                  onPressed: onReset,
                  icon: const Icon(Icons.fit_screen_rounded),
                ),
                const SizedBox(width: LumaSpacing.xs),
                _deleteButton(theme, chromeStyle),
                const SizedBox(width: LumaSpacing.xs),
                closeButton,
              ],
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: extras.badgeScrim,
        borderRadius: BorderRadius.circular(LumaRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _TvPreviewAction(
              focusNode: toolbarFocusNode,
              autofocus: true,
              tooltip: '放大',
              label: '放大',
              icon: Icons.zoom_in_rounded,
              onPressed: zoomIn,
            ),
            _TvPreviewAction(
              tooltip: '缩小',
              label: '缩小',
              icon: Icons.zoom_out_rounded,
              onPressed: zoomOut,
            ),
            _TvPreviewAction(
              tooltip: '还原',
              label: '还原',
              icon: Icons.aspect_ratio_rounded,
              onPressed: onReset,
            ),
            _TvPreviewAction(
              tooltip: '详情',
              label: '详情',
              icon: Icons.info_outline_rounded,
              onPressed: onDetails,
            ),
            const Spacer(),
            _tvDeleteButton(theme),
            _TvPreviewAction(
              tooltip: '关闭',
              label: '关闭',
              icon: Icons.close_rounded,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }

  /// 普通端删除按钮：进行中用进度圈占位并保持原宽，禁用态置灰。
  Widget _deleteButton(ThemeData theme, ButtonStyle chromeStyle) {
    return IconButton.filledTonal(
      tooltip: '删除图片',
      style: chromeStyle,
      onPressed: onDelete,
      icon: deleteInProgress
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.error,
              ),
            )
          : Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
    );
  }

  /// TV 删除动作：带文字的可聚焦大按钮，与工具栏其余动作同规格。
  Widget _tvDeleteButton(ThemeData theme) {
    return Tooltip(
      message: '删除图片',
      child: TextButton.icon(
        onPressed: onDelete,
        icon: deleteInProgress
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.error,
                ),
              )
            : Icon(
                Icons.delete_outline_rounded,
                color: theme.colorScheme.error,
              ),
        label: Text(
          deleteInProgress ? '删除中' : '删除',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    );
  }
}

class _TvPreviewAction extends StatelessWidget {
  const _TvPreviewAction({
    required this.tooltip,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });

  final String tooltip;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton.icon(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}
