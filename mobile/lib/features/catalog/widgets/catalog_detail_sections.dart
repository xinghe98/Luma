// 作品详情的资料、演员、版本和剧集条目组件集中在此文件。
// 组件只渲染传入的资料，播放行为始终交还给详情页面的回调。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../../../shared/interaction/luma_focusable_surface.dart';
import '../../../shared/media/authenticated_media_image.dart';
import '../../../shared/media/media_card.dart';

/// 显示详情分区标题及可选的右侧摘要。
class CatalogSectionHeading extends StatelessWidget {
  const CatalogSectionHeading({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
    ],
  );
}

/// 横向显示演员头像，图片容器先固定为正方形再裁成正圆。
class CatalogCreditStrip extends StatelessWidget {
  /// 普通端保留横向头像条，电视端展开完整演职员供上下键逐屏阅读。
  const CatalogCreditStrip({
    super.key,
    required this.credits,
    this.television = false,
  });

  final List<CatalogCredit> credits;
  final bool television;

  @override
  Widget build(BuildContext context) {
    if (television) {
      return Wrap(
        spacing: LumaSpacing.lg,
        runSpacing: LumaSpacing.lg,
        children: [
          for (final credit in credits)
            SizedBox(
              width: 168,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipOval(
                    child: SizedBox.square(
                      dimension: 72,
                      child: AuthenticatedMediaImage(
                        path: credit.profileUrl,
                        cacheWidth: 144,
                        cacheHeight: 144,
                        fallback: ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          child: const Icon(Icons.person_rounded),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: LumaSpacing.sm),
                  Text(
                    credit.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (credit.character.isNotEmpty)
                    Text(
                      credit.character,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
        ],
      );
    }
    final cast = credits
        .where((credit) => credit.role == 'actor')
        .take(12)
        .toList();
    final visibleCredits = cast.isEmpty ? credits.take(12).toList() : cast;
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visibleCredits.length,
        separatorBuilder: (_, _) => const SizedBox(width: LumaSpacing.md),
        itemBuilder: (context, index) =>
            _CreditPortrait(credit: visibleCredits[index]),
      ),
    );
  }
}

class _CreditPortrait extends StatelessWidget {
  const _CreditPortrait({required this.credit});

  final CatalogCredit credit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 60,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(
          child: SizedBox.square(
            dimension: 56,
            child: AuthenticatedMediaImage(
              path: credit.profileUrl,
              cacheWidth: 112,
              cacheHeight: 112,
              fit: BoxFit.cover,
              fallback: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Icon(
                  Icons.person_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: LumaSpacing.xs),
        Text(
          credit.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (credit.character.isNotEmpty)
          Text(
            credit.character,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

/// 显示一个可播放的本地电影版本及其技术资料。
class CatalogVersionTile extends StatelessWidget {
  const CatalogVersionTile({
    super.key,
    required this.version,
    required this.onPlay,
    this.focusId,
    this.autofocus = false,
    this.onFocusChange,
    this.focusBorderWidth = 2,
  });

  final CatalogVersion version;
  final VoidCallback onPlay;

  /// TV 集合内的稳定身份；非空时改用 LumaFocusableSurface 承载焦点描边。
  final String? focusId;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final double focusBorderWidth;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (version.videoCodec.isNotEmpty) version.videoCodec.toUpperCase(),
      if (version.audioCodec.isNotEmpty) version.audioCodec.toUpperCase(),
    ].join(' · ');
    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: LumaSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          _VersionBadge(label: version.label, resolution: version.resolution),
          const SizedBox(width: LumaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  version.label.isEmpty ? '本地版本' : version.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (metadata.isNotEmpty)
                  Text(
                    metadata,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (version.fileSize > 0)
            Text(
              _formatFileSize(version.fileSize),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: LumaSpacing.sm),
          Icon(
            Icons.chevron_right_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
    // TV 路径：焦点描边由 LumaFocusableSurface 提供，激活仍走原回调。
    if (focusId != null) {
      return LumaFocusableSurface(
        label: '播放${version.label.isEmpty ? '本地版本' : version.label}',
        onActivate: onPlay,
        borderRadius: BorderRadius.circular(LumaRadii.small),
        focusId: focusId,
        autofocus: autofocus,
        onFocusChange: onFocusChange,
        focusBorderWidth: focusBorderWidth,
        child: content,
      );
    }
    return InkWell(onTap: onPlay, child: content);
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({required this.label, required this.resolution});

  final String label;
  final String resolution;

  @override
  Widget build(BuildContext context) {
    final value = '$resolution $label'.toUpperCase();
    final display = switch (value) {
      final text when text.contains('2160') || text.contains('4K') => '4K\nUHD',
      final text when text.contains('1080') => '1080p\nFHD',
      final text when text.contains('720') => '720p\nHD',
      final text when text.contains('576') || text.contains('480') => 'SD',
      _ => resolution.trim().isEmpty ? '本地\n版本' : resolution.trim(),
    };
    return Container(
      width: 50,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        borderRadius: BorderRadius.circular(LumaRadii.small),
      ),
      child: Text(
        display,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 显示刮削任务的非正常状态，不替换用户可阅读的资料内容。
class CatalogMetadataStatus extends StatelessWidget {
  const CatalogMetadataStatus({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final message = switch (status) {
      'pending' => '资料等待更新',
      'refreshing' => '资料正在更新',
      'needs_review' => '资料匹配需要确认',
      'failed' => '资料暂时无法更新',
      _ => '资料状态更新中',
    };
    return Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// 显示一个可播放的剧集条目，点击时由上层打开对应媒体。
class CatalogEpisodeTile extends StatelessWidget {
  const CatalogEpisodeTile({
    super.key,
    required this.episode,
    required this.onTap,
    this.focusId,
    this.autofocus = false,
    this.onFocusChange,
    this.focusBorderWidth = 2,
  });

  final CatalogEpisode episode;
  final VoidCallback onTap;

  /// TV 集合内的稳定身份；非空时改用 LumaFocusableSurface 承载焦点描边。
  final String? focusId;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final double focusBorderWidth;

  /// 行高与远程揭示共用，容纳系统缩放后的两行标题和元数据。
  static double televisionExtent(BuildContext context) {
    final textHeight = MediaCard.textDetailsHeight(context);
    const artworkHeight = 112 * 9 / 16;
    return (textHeight > artworkHeight ? textHeight : artworkHeight) +
        LumaSpacing.md;
  }

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (episode.durationMs != null)
        formatDuration(Duration(milliseconds: episode.durationMs!)),
      if (episode.resolution.isNotEmpty) episode.resolution,
    ].join(' · ');
    final content = Row(
      children: [
        SizedBox(
          width: 112,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LumaRadii.small),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: AuthenticatedMediaImage(
                path: episode.thumbnailUrl,
                cacheWidth: 224,
                fallback: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  child: Icon(
                    Icons.play_circle_outline_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: LumaSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第 ${episode.episodeNumber} 集 · ${episode.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (metadata.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: LumaSpacing.xs),
                  child: Text(
                    metadata,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Icon(
          Icons.play_arrow_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    );
    final body = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: LumaSpacing.md),
        child: content,
      ),
    );
    if (focusId == null) return body;
    // TV 路径：整行成为单一焦点目标，描边由 LumaFocusableSurface 提供。
    return LumaFocusableSurface(
      label: '第 ${episode.episodeNumber} 集 · ${episode.title}',
      onActivate: onTap,
      borderRadius: BorderRadius.circular(LumaRadii.small),
      focusId: focusId,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      focusBorderWidth: focusBorderWidth,
      child: content,
    );
  }
}

String _formatFileSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
