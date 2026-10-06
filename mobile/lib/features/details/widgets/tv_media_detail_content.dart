// 电视媒体详情展示观看首屏与下方只读资料，复用页面持有的控制器、海报和焦点。
// 此组件不请求媒体、不持有播放会话，销毁仍由详情页面负责。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_types.dart';
import '../../../shared/formatters/duration_formatter.dart';
import '../details_controller.dart';
import 'detail_actions.dart';
import 'playback_progress.dart';
import 'tv_scrollable_detail_region.dart';

/// 将电视媒体详情组织为横向观看区域和可遥控阅读的文件资料。
class TvMediaDetailContent extends StatelessWidget {
  const TvMediaDetailContent({
    super.key,
    required this.controller,
    required this.artwork,
    required this.playFocusNode,
    required this.autofocusPrimary,
  });

  final DetailsController controller;
  final Widget artwork;
  final FocusNode playFocusNode;
  final bool autofocusPrimary;

  @override
  Widget build(BuildContext context) {
    final item = controller.item!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => Stack(
            key: const ValueKey('tv-media-viewing-header'),
            children: [
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: constraints.maxWidth * 0.62,
                child: artwork,
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.surface,
                        theme.colorScheme.surface,
                        theme.colorScheme.surface.withValues(alpha: 0.4),
                        theme.colorScheme.surface.withValues(alpha: 0),
                        theme.colorScheme.surface.withValues(alpha: 0.35),
                      ],
                      stops: const [0, 0.24, 0.46, 0.7, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(LumaSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 288),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: constraints.maxWidth >= 900
                          ? constraints.maxWidth * 0.58
                          : constraints.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineLarge,
                          ),
                          const SizedBox(height: LumaSpacing.sm),
                          Text(
                            [
                              item.resolution,
                              item.format,
                            ].where((value) => value.isNotEmpty).join(' · '),
                            style: theme.textTheme.bodyLarge,
                          ),
                          const SizedBox(height: LumaSpacing.lg),
                          DetailActions(
                            controller: controller,
                            television: true,
                            autofocusPrimary: autofocusPrimary,
                            connectFocusNode: playFocusNode,
                          ),
                          PlaybackProgress(item: item),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LumaSpacing.xl),
        TvScrollableDetailRegion(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: LumaSpacing.sm),
              Wrap(
                spacing: LumaSpacing.xl,
                runSpacing: LumaSpacing.lg,
                children: [
                  if (item.type == MediaType.video)
                    _TvMediaField(
                      label: '时长',
                      value: formatDuration(item.duration),
                    ),
                  _TvMediaField(label: '分辨率', value: item.resolution),
                  _TvMediaField(label: '格式', value: item.format),
                  _TvMediaField(label: '文件大小', value: item.fileSize),
                ],
              ),
              if (item.tags.isNotEmpty) ...[
                const SizedBox(height: LumaSpacing.xl),
                Text('标签', style: theme.textTheme.titleMedium),
                Text(item.tags.join(' · '), style: theme.textTheme.bodyLarge),
              ],
              if (item.note.isNotEmpty) ...[
                const SizedBox(height: LumaSpacing.xl),
                Text('笔记', style: theme.textTheme.titleMedium),
                const SizedBox(height: LumaSpacing.sm),
                Text(item.note, style: theme.textTheme.bodyLarge),
              ],
              const SizedBox(height: LumaSpacing.xl),
              Text('文件信息', style: theme.textTheme.titleMedium),
              const SizedBox(height: LumaSpacing.sm),
              Text('媒体源', style: theme.textTheme.bodyMedium),
              Text(
                item.sourceName.isEmpty ? item.sourceId : item.sourceName,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: LumaSpacing.md),
              Text('文件名', style: theme.textTheme.bodyMedium),
              Text(item.filename, style: theme.textTheme.bodyLarge),
              if (item.directory.isNotEmpty) ...[
                const SizedBox(height: LumaSpacing.md),
                Text('目录', style: theme.textTheme.bodyMedium),
                Text(item.directory, style: theme.textTheme.bodyLarge),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TvMediaField extends StatelessWidget {
  const _TvMediaField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: LumaSpacing.xs),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}
