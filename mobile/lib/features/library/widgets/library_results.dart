import 'package:flutter/material.dart';

import '../../../app/controllers/media_controller.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/media/media_actions.dart';
import '../../../shared/states/empty_state.dart';
import '../../../shared/states/media_grid_state.dart';

class LibraryResults extends StatelessWidget {
  const LibraryResults({
    super.key,
    required this.media,
    required this.items,
    required this.heroTagPrefix,
    required this.emptyHint,
    required this.onOpenMedia,
    required this.onFavorite,
    required this.onClear,
    this.loadState,
    this.onRetry,
  });

  final MediaController media;
  final List<MediaItem> items;
  final String heroTagPrefix;
  final String emptyHint;
  final MediaOpenCallback onOpenMedia;
  final ValueChanged<MediaItem> onFavorite;
  final VoidCallback onClear;
  final LoadState? loadState;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MediaGridState(
      loadState: loadState ?? media.loadState,
      items: items,
      heroTagPrefix: heroTagPrefix,
      onRetry: onRetry ?? media.load,
      onOpenMedia: onOpenMedia,
      onFavorite: onFavorite,
      emptyState: EmptyState(
        title: emptyHint,
        message: '尝试清除筛选条件，或等待服务器扫描完成。',
        icon: Icons.filter_alt_off_outlined,
        action: OutlinedButton(onPressed: onClear, child: const Text('清除筛选条件')),
      ),
    );
  }
}
