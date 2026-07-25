import 'package:flutter/material.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/models/media_item.dart';
import '../media/media_actions.dart';
import '../media/responsive_media_grid.dart';
import 'error_state.dart';
import 'skeleton.dart';

class MediaGridState extends StatelessWidget {
  const MediaGridState({
    super.key,
    required this.loadState,
    required this.items,
    required this.heroTagPrefix,
    required this.emptyState,
    required this.onRetry,
    required this.onOpenMedia,
    required this.onFavorite,
  });

  final LoadState loadState;
  final List<MediaItem> items;
  final String heroTagPrefix;
  final Widget emptyState;
  final VoidCallback onRetry;
  final MediaOpenCallback onOpenMedia;
  final ValueChanged<MediaItem> onFavorite;

  @override
  Widget build(BuildContext context) => switch (loadState) {
    LoadState.loading when items.isEmpty => const MediaGridSkeleton(items: 8),
    LoadState.loading => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LinearProgressIndicator(minHeight: 2),
        _mediaGrid(),
      ],
    ),
    LoadState.error when items.isNotEmpty => _mediaGrid(),
    LoadState.error => ErrorState(onRetry: onRetry),
    _ when items.isEmpty => emptyState,
    _ => _mediaGrid(),
  };

  Widget _mediaGrid() => ResponsiveMediaGrid(
      items: items,
      heroTagPrefix: heroTagPrefix,
      onTap: onOpenMedia,
      onFavorite: onFavorite,
      // 嵌在外层滚动视图时保持 shrinkWrap；条目已由仓库侧分页上限控制。
      shrinkWrap: true,
    );
}
