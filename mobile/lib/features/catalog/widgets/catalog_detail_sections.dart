// 作品详情的资料、演员、版本和剧集条目组件集中在此文件。
// 组件只渲染传入的资料，播放行为始终交还给详情页面的回调。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../../../shared/media/authenticated_media_image.dart';
import 'catalog_detail_theme.dart';

/// 显示详情分区标题及可选的右侧摘要。
class CatalogSectionHeading extends StatelessWidget {
  const CatalogSectionHeading({super.key, required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      if (trailing != null)
        Text(
          trailing!,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: CatalogDetailPalette.muted),
        ),
    ],
  );
}

/// 横向显示演员头像，图片容器先固定为正方形再裁成正圆。
class CatalogCreditStrip extends StatelessWidget {
  const CatalogCreditStrip({super.key, required this.credits});

  final List<CatalogCredit> credits;

  @override
  Widget build(BuildContext context) {
    final cast = credits.where((credit) => credit.role == 'actor').take(12).toList();
    final visibleCredits = cast.isEmpty ? credits.take(12).toList() : cast;
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visibleCredits.length,
        separatorBuilder: (_, _) => const SizedBox(width: LumaSpacing.md),
        itemBuilder: (context, index) => _CreditPortrait(
          credit: visibleCredits[index],
        ),
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
              fallback: const ColoredBox(
                color: Color(0xFF30312B),
                child: Icon(Icons.person_rounded, color: CatalogDetailPalette.muted),
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: CatalogDetailPalette.muted),
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
  });

  final CatalogVersion version;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (version.videoCodec.isNotEmpty) version.videoCodec.toUpperCase(),
      if (version.audioCodec.isNotEmpty) version.audioCodec.toUpperCase(),
      if (version.fileSize > 0) _formatFileSize(version.fileSize),
    ].join(' · ');
    return InkWell(
      onTap: onPlay,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: LumaSpacing.sm),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF403D34))),
        ),
        child: Row(
          children: [
            _VersionBadge(label: version.label),
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
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(
                        color: CatalogDetailPalette.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (version.fileSize > 0)
              Text(
                _formatFileSize(version.fileSize),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(
                  color: CatalogDetailPalette.muted,
                ),
              ),
            const SizedBox(width: LumaSpacing.sm),
            const Icon(
              Icons.chevron_right_rounded,
              color: CatalogDetailPalette.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final display = label.toUpperCase().contains('4K') ? '4K\nHDR' : '1080p\nFHD';
    return Container(
      width: 50,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: CatalogDetailPalette.muted),
        borderRadius: BorderRadius.circular(LumaRadii.small),
      ),
      child: Text(
        display,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: CatalogDetailPalette.text),
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
  });

  final CatalogEpisode episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (episode.durationMs != null)
        formatDuration(Duration(milliseconds: episode.durationMs!)),
      if (episode.resolution.isNotEmpty) episode.resolution,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: LumaSpacing.md),
        child: Row(
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
                    fallback: const ColoredBox(
                      color: Color(0xFF30312B),
                      child: Icon(
                        Icons.play_circle_outline_rounded,
                        color: CatalogDetailPalette.muted,
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
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(
                          color: CatalogDetailPalette.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Icons.play_arrow_rounded,
              color: CatalogDetailPalette.muted,
            ),
          ],
        ),
      ),
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
