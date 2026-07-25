import 'package:flutter/material.dart';

import '../app/controllers/media_controller.dart';
import '../data/models/media_item.dart';

extension LumaSnackBar on BuildContext {
  /// 统一的轻提示入口，避免各处重复拼装 [SnackBar]。
  void showLumaSnack(String message) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> toggleFavoriteWithFeedback(
    MediaController media,
    MediaItem item,
  ) async {
    final nextFavorite = !item.isFavorite;
    try {
      media.remember(item, notify: false);
      await media.toggleFavorite(item.id);
      if (!mounted) return;
      showLumaSnack(nextFavorite ? '已加入收藏' : '已取消收藏');
    } on Object catch (error) {
      if (!mounted) return;
      showLumaSnack('收藏失败：$error');
    }
  }
}
