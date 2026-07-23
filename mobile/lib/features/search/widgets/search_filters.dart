import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_types.dart';
import '../../../data/models/api_tag.dart';
import '../../../shared/layout/section_header.dart';

class SearchFilters extends StatelessWidget {
  const SearchFilters({
    super.key,
    required this.type,
    required this.tagId,
    required this.tags,
    required this.onType,
    required this.onTag,
  });

  final MediaType? type;
  final String? tagId;
  final List<Tag> tags;
  final ValueChanged<MediaType?> onType;
  final void Function(String id, String name) onTag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: LumaSpacing.lg),
        const SectionHeader(title: '类型与标签'),
        const SizedBox(height: LumaSpacing.sm),
        const _GroupLabel('类型'),
        const SizedBox(height: LumaSpacing.xs),
        Wrap(
          spacing: LumaSpacing.xs,
          runSpacing: LumaSpacing.xs,
          children: [
            ChoiceChip(
              label: const Text('全部'),
              selected: type == null,
              onSelected: (_) => onType(null),
            ),
            ChoiceChip(
              label: const Text('视频'),
              selected: type == MediaType.video,
              onSelected: (_) => onType(MediaType.video),
            ),
            ChoiceChip(
              label: const Text('图片'),
              selected: type == MediaType.image,
              onSelected: (_) => onType(MediaType.image),
            ),
          ],
        ),
        const SizedBox(height: LumaSpacing.md),
        const _GroupLabel('标签'),
        const SizedBox(height: LumaSpacing.xs),
        if (tags.isEmpty)
          Text(
            '暂无标签',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          )
        else
          Wrap(
            spacing: LumaSpacing.xs,
            runSpacing: LumaSpacing.xs,
            children: tags
                .map(
                  (value) => FilterChip(
                    label: Text(value.name),
                    selected: tagId == value.id,
                    onSelected: (_) => onTag(value.id, value.name),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
