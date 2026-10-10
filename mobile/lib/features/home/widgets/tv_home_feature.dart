// TV 首页首屏从已有媒体摘要呈现内容与主操作，交由 HomePage 处理导航和刷新。
// 不发起额外请求或轮播计时，媒体更新时随首页重建，焦点始终留在原操作节点。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../data/models/media_types.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../../../shared/media/media_artwork.dart';

class TvHomeFeature extends StatelessWidget {
  /// 展示首项继续观看或最近媒体；无内容时保留可操作的刷新入口。
  const TvHomeFeature({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onRefresh,
  });

  final MediaItem? item;
  final VoidCallback onOpen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = item;
    final colors = theme.colorScheme;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          media != null && media.progress > 0 ? '接着上次看' : '你的媒体，随时开场',
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          media?.title ?? '家庭放映室',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineLarge,
        ),
        if (media != null) ...[
          const SizedBox(height: LumaSpacing.sm),
          Text(
            [
              if (media.type == MediaType.video) formatDuration(media.duration),
              if (media.type == MediaType.image) '图片',
              if (media.resolution.isNotEmpty) media.resolution,
              if (media.progress > 0 && media.type == MediaType.video)
                '已观看 ${(media.progress * 100).round()}%',
            ].where((value) => value.isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (media.progress > 0 && media.type == MediaType.video) ...[
            const SizedBox(height: LumaSpacing.sm),
            SizedBox(
              width: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(LumaRadii.small),
                child: LinearProgressIndicator(
                  value: media.progress,
                  minHeight: 6,
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: LumaSpacing.md),
        Wrap(
          spacing: LumaSpacing.sm,
          runSpacing: LumaSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (media != null)
              FilledButton.icon(
                key: const ValueKey('tv-home-open-feature'),
                onPressed: onOpen,
                icon: Icon(
                  media.type == MediaType.video
                      ? Icons.play_circle_outline_rounded
                      : Icons.image_outlined,
                ),
                label: Text(
                  media.type == MediaType.image
                      ? '查看图片'
                      : media.progress > 0
                      ? '继续播放'
                      : '播放',
                ),
              ),
            IconButton.outlined(
              tooltip: '刷新媒体库',
              onPressed: onRefresh,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(LumaTvLayout.controlMinHeight),
              ),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= LumaTvLayout.featureMinWidth;
        final artwork = media == null
            ? null
            : MediaArtwork(
                item: media,
                useCardThumbnail: media.type == MediaType.video,
                borderRadius: 0,
                fit: media.type == MediaType.image
                    ? BoxFit.contain
                    : BoxFit.cover,
              );
        if (!wide) {
          return Padding(
            key: const ValueKey('tv-home-feature'),
            padding: const EdgeInsets.all(LumaLayout.pagePaddingH),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (artwork != null) ...[
                  AspectRatio(aspectRatio: 16 / 9, child: artwork),
                  const SizedBox(height: LumaSpacing.lg),
                ],
                details,
              ],
            ),
          );
        }
        final viewportHeight = MediaQuery.sizeOf(context).height;
        final heroHeight = (viewportHeight * 0.48).clamp(252.0, 320.0);
        return SizedBox(
          key: const ValueKey('tv-home-feature'),
          height: heroHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (artwork != null)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: constraints.maxWidth * 0.62,
                  child: artwork,
                ),
              const _HeroFade(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LumaLayout.pagePaddingH,
                  LumaSpacing.md,
                  LumaLayout.pagePaddingH,
                  LumaSpacing.md,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: constraints.maxWidth * 0.5,
                    child: details,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroFade extends StatelessWidget {
  const _HeroFade();

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LumaGradients.sideFade(background),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0x00000000),
                  background.withValues(alpha: 0),
                  background,
                ],
                stops: const [0, 0.62, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
