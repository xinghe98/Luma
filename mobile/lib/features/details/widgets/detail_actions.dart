import 'package:flutter/material.dart';

import '../../../core/extensions.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/media_types.dart';
import '../../player/player_page.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () => _toggleFavorite(context, item),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              key: ValueKey(item.isFavorite),
              item.isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
          ),
          label: Text(item.isFavorite ? '已收藏' : '收藏'),
        ),
      ],
    );
  }

  void _openPrimary(BuildContext context, MediaItem item) {
    if (item.type == MediaType.image) {
      // 详情内已在详情页，预览无需再提供「详情」入口。
      showImagePreviewDialog(context, item);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerPage(mediaId: item.id)),
    );
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
