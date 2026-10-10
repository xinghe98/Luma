import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/media_types.dart';
import '../../../shared/layout/adaptive_action_width.dart';
import '../../../shared/interaction/luma_focusable_surface.dart';
import '../../../shared/media/media_artwork.dart';
import '../../../shared/media/cover_progress_bar.dart';
import 'home_layout.dart';

/// 首页「继续观看」主打卡片：封面、剩余时间、直接播放按钮。
/// 宽屏时在右侧列出最多 3 条待播项，窄屏只展示主卡。
class ContinueSpotlight extends StatelessWidget {
  const ContinueSpotlight({
    super.key,
    required this.item,
    required this.upNext,
    required this.onOpen,
  });

  /// 当前继续观看的首项。
  final MediaItem item;

  /// 宽屏侧栏展示的后续待播项，最多取前 3 条。
  final List<MediaItem> upNext;

  /// 点击进入媒体详情；封面点击与「接着看」行复用此回调。
  final ValueChanged<MediaItem> onOpen;

  /// 按媒体剩余时长估算的分钟数，最小 1。
  static int remainingMinutes(MediaItem item) {
    final left = item.duration.inMilliseconds * (1 - item.progress);
    return (left / 60000).ceil().clamp(1, 1 << 31);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = HomeLayout.sideInset(constraints.maxWidth);
        final padding = EdgeInsets.symmetric(
          horizontal: inset,
          vertical: LumaSpacing.md,
        );
        final wide =
            constraints.maxWidth >= LumaLayout.navigationRailBreakpoint;
        if (wide && upNext.isNotEmpty) {
          return Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 7,
                  child: _SpotlightCard(item: item, onOpen: onOpen),
                ),
                const SizedBox(width: LumaSpacing.lg),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '接着看',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: LumaSpacing.sm),
                      for (final next in upNext.take(3))
                        _UpNextRow(item: next, onOpen: onOpen),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: padding,
          child: _SpotlightCard(item: item, onOpen: onOpen),
        );
      },
    );
  }
}

/// 主卡：16:9 封面 + 进度条 + 标题 + 元信息 + 播放按钮。
class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({required this.item, required this.onOpen});

  final MediaItem item;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remaining = ContinueSpotlight.remainingMinutes(item);
    final meta = [
      '剩余 $remaining 分钟',
      if (item.resolution.isNotEmpty) item.resolution,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumaFocusableSurface(
          label: '打开详情：${item.title}',
          onActivate: () => onOpen(item),
          borderRadius: BorderRadius.circular(LumaRadii.large),
          paintHoverFill: false,
          child: LumaCoverLift(
            borderRadius: BorderRadius.circular(LumaRadii.large),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(LumaRadii.large),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaArtwork(
                      item: item,
                      useCardThumbnail: item.type == MediaType.video,
                      borderRadius: 0,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: CoverProgressBar(
                        progress: item.progress,
                        height: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        Text(item.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: LumaSpacing.xxs),
        Text(
          meta,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        AdaptiveActionWidth(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () =>
                unawaited(context.openPlayer(item.id, initialItem: item)),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('继续播放'),
          ),
        ),
      ],
    );
  }
}

/// 宽屏侧栏单条待播：112 宽缩略图 + 标题 + 进度。
class _UpNextRow extends StatelessWidget {
  const _UpNextRow({required this.item, required this.onOpen});

  final MediaItem item;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: LumaSpacing.sm),
      child: LumaFocusableSurface(
        label: item.title,
        borderRadius: BorderRadius.circular(LumaRadii.medium),
        onActivate: () => onOpen(item),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(LumaRadii.cover),
              child: SizedBox(
                width: 112,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MediaArtwork(
                        item: item,
                        useCardThumbnail: item.type == MediaType.video,
                        borderRadius: 0,
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: CoverProgressBar(progress: item.progress),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: LumaSpacing.sm),
            Expanded(
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
