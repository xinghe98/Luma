import 'package:flutter/material.dart';

import '../../../app/app_router.dart';
import '../../../core/extensions.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/media_types.dart';
import '../../../shared/layout/adaptive_action_width.dart';
import '../details_controller.dart';
import '../dialogs/image_preview_dialog.dart';

class DetailActions extends StatelessWidget {
  const DetailActions({
    super.key,
    required this.controller,
    this.television = false,
    this.autofocusPrimary = false,
    this.connectFocusNode,
  });

  final DetailsController controller;

  /// TV：收藏改为带文字的可见按钮（≥56dp），主操作在首次有效内容时获焦。
  final bool television;

  /// TV 首次有效内容聚焦主播放；不可播放时由详情页落在收藏。
  final bool autofocusPrimary;

  /// 主播放按钮的焦点节点；TV 详情页用于首帧聚焦。
  final FocusNode? connectFocusNode;

  @override
  Widget build(BuildContext context) {
    final item = controller.item;
    if (item == null) return const SizedBox.shrink();
    final canPlay = item.type != MediaType.video || item.status == 'ready';
    final favoriteButton = television
        // TV：带文字的可见收藏按钮，最小高度与控件规格一致；
        // 不可播放时 TV 首焦点落在收藏按钮上。
        ? OutlinedButton.icon(
            key: const ValueKey('detail-favorite-action'),
            focusNode: canPlay ? null : connectFocusNode,
            onFocusChange: _revealAction,
            autofocus: autofocusPrimary && !canPlay,
            onPressed: () => _toggleFavorite(context, item),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, LumaTvLayout.controlMinHeight),
            ),
            icon: Icon(
              item.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
            label: Text(item.isFavorite ? '已收藏' : '收藏'),
          )
        : SizedBox.square(
            key: const ValueKey('detail-favorite-action'),
            dimension: LumaLayout.buttonHeight,
            child: IconButton.outlined(
              tooltip: item.isFavorite ? '取消收藏' : '收藏',
              onPressed: () => _toggleFavorite(context, item),
              isSelected: item.isFavorite,
              icon: AnimatedSwitcher(
                duration: LumaMotion.forContext(context, LumaMotion.fast),
                switchInCurve: LumaMotion.standard,
                switchOutCurve: LumaMotion.standard,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Icon(
                  key: ValueKey(item.isFavorite),
                  item.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
              ),
            ),
          );
    if (television) {
      return AdaptiveActionWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              focusNode: canPlay ? connectFocusNode : null,
              onFocusChange: _revealAction,
              autofocus: autofocusPrimary && canPlay,
              onPressed: canPlay ? () => _openPrimary(context, item) : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, LumaTvLayout.controlMinHeight),
              ),
              icon: Icon(
                item.type == MediaType.video
                    ? Icons.play_arrow_rounded
                    : Icons.fullscreen_rounded,
              ),
              label: Text(
                item.type == MediaType.video
                    ? (item.status != 'ready'
                          ? '尚未就绪'
                          : (item.progress > 0 ? '继续播放' : '播放'))
                    : '查看大图',
              ),
            ),
            const SizedBox(height: LumaSpacing.sm),
            favoriteButton,
          ],
        ),
      );
    }
    return AdaptiveActionWidth(
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: canPlay ? () => _openPrimary(context, item) : null,
              icon: Icon(
                item.type == MediaType.video
                    ? Icons.play_arrow_rounded
                    : Icons.fullscreen_rounded,
              ),
              label: Text(
                item.type == MediaType.video
                    ? (item.status != 'ready'
                          ? '尚未就绪'
                          : (item.progress > 0 ? '继续播放' : '播放'))
                    : '查看大图',
              ),
            ),
          ),
          const SizedBox(width: LumaSpacing.sm),
          favoriteButton,
        ],
      ),
    );
  }

  void _revealAction(bool focused) {
    if (!television || !focused) return;
    final node = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node?.context;
      if (context != null && context.mounted && node!.hasPrimaryFocus) {
        Scrollable.ensureVisible(context, alignment: 0.5);
      }
    });
  }

  void _openPrimary(BuildContext context, MediaItem item) {
    if (item.type == MediaType.image) {
      showImagePreviewDialog(context, item);
      return;
    }
    context.openPlayer(item.id, initialItem: item);
  }

  Future<void> _toggleFavorite(BuildContext context, MediaItem item) async {
    final nextFavorite = !item.isFavorite;
    try {
      await controller.toggleFavorite();
      if (!context.mounted) return;
      context.showLumaSnack(nextFavorite ? '已加入收藏' : '已取消收藏');
    } on Object catch (error) {
      if (!context.mounted) return;
      context.showLumaSnack('收藏失败：$error');
    }
  }
}
