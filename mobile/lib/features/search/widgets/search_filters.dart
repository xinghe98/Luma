import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/media_types.dart';
import '../../../data/models/api_tag.dart';

class SearchFilters extends StatelessWidget {
  const SearchFilters({
    super.key,
    required this.type,
    required this.tagId,
    required this.tags,
    required this.onType,
    required this.onTag,
    this.television = false,
  });

  final MediaType? type;
  final String? tagId;
  final List<Tag> tags;
  final ValueChanged<MediaType?> onType;
  final void Function(String id, String name) onTag;

  /// TV 将类型保留为单行选择，将全部标签收纳到可遥控菜单。
  final bool television;

  @override
  Widget build(BuildContext context) {
    if (television) {
      final selectedTags = tags.where((tag) => tag.id == tagId);
      final selectedTag = selectedTags.isEmpty ? null : selectedTags.first;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final option in <(MediaType?, String)>[
              (null, '全部'),
              (MediaType.video, '视频'),
              (MediaType.image, '图片'),
            ]) ...[
              ChoiceChip(
                label: Text(option.$2),
                selected: type == option.$1,
                onSelected: (_) => onType(option.$1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              const SizedBox(width: 12),
            ],
            PopupMenuButton<String>(
              tooltip: '选择标签',
              onSelected: (id) {
                final tag = tags.firstWhere((tag) => tag.id == id);
                onTag(tag.id, tag.name);
              },
              itemBuilder: (_) => [
                for (final tag in tags)
                  CheckedPopupMenuItem(
                    value: tag.id,
                    checked: tag.id == tagId,
                    child: Text(tag.name),
                  ),
              ],
              enabled: tags.isNotEmpty,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.label_outline_rounded),
                    const SizedBox(width: 10),
                    Text(selectedTag?.name ?? '标签'),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: LumaSpacing.md),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('全部'),
              selected: type == null,
              onSelected: (_) => onType(null),
            ),
            const SizedBox(width: LumaSpacing.xs),
            ChoiceChip(
              label: const Text('视频'),
              selected: type == MediaType.video,
              onSelected: (_) => onType(MediaType.video),
            ),
            const SizedBox(width: LumaSpacing.xs),
            ChoiceChip(
              label: const Text('图片'),
              selected: type == MediaType.image,
              onSelected: (_) => onType(MediaType.image),
            ),
            if (tags.isNotEmpty)
              for (final value in tags) ...[
                const SizedBox(width: LumaSpacing.xs),
                FilterChip(
                  label: Text(value.name),
                  selected: tagId == value.id,
                  onSelected: (_) => onTag(value.id, value.name),
                ),
              ],
          ],
        ),
      ),
    );
  }
}
