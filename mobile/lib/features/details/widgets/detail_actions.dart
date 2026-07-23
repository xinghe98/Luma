import 'package:flutter/material.dart';

import '../../../app/app_router.dart';
import '../../../core/extensions.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/media_types.dart';
import '../details_controller.dart';
import '../dialogs/image_preview_dialog.dart';

class DetailActions extends StatelessWidget {
  const DetailActions({super.key, required this.controller});

  final DetailsController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.item;
    if (item == null) return const SizedBox.shrink();
    final canPlay = item.type != MediaType.video || item.status == 'ready';
    return Row(
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
        SizedBox.square(
          key: const ValueKey('detail-favorite-action'),
          dimension: LumaLayout.buttonHeight,
          child: IconButton.outlined(
            tooltip: item.isFavorite ? '取消收藏' : '收藏',
            onPressed: () => _toggleFavorite(context, item),
            isSelected: item.isFavorite,
            icon: AnimatedSwitcher(
              duration: LumaMotion.fast,
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
        ),
      ],
    );
  }

  void _openPrimary(BuildContext context, MediaItem item) {
    if (item.type == MediaType.image) {
      showImagePreviewDialog(context, item);
      return;
    }
    context.openPlayer(item.id);
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
