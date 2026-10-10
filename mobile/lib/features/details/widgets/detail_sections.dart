import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_scope.dart';
import '../../../features/search/search_request.dart';
import '../../../features/shell/app_destination.dart';
import '../../../core/extensions.dart';
import '../../../core/theme.dart';
import '../../../data/models/media_item.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/layout/surface_card.dart';
import '../details_controller.dart';
import '../dialogs/note_editor_dialog.dart';

class DetailSections extends StatelessWidget {
  const DetailSections({super.key, required this.controller});

  final DetailsController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.item;
    if (item == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '标签'),
        const SizedBox(height: LumaSpacing.xs),
        Wrap(
          spacing: LumaSpacing.xs,
          runSpacing: LumaSpacing.xs,
          children: item.tags
              .map(
                (tag) => ActionChip(
                  label: Text(tag),
                  onPressed: () => _searchTag(context, tag),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: LumaSpacing.xl),
        SectionHeader(
          title: '笔记',
          action: TextButton.icon(
            onPressed: () => _editNote(context, item),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('编辑'),
          ),
        ),
        SurfaceCard(
          child: Text(
            item.note.isEmpty ? '还没有笔记。记录关于这段影像的想法。' : item.note,
            style: TextStyle(
              color: item.note.isEmpty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
        ),
        if (item.directory.isNotEmpty) ...[
          const SizedBox(height: LumaSpacing.xl),
          const SectionHeader(title: '文件信息'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage_rounded),
            title: const Text('媒体源'),
            subtitle: Text(
              item.sourceName.isEmpty ? item.sourceId : item.sourceName,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('文件名'),
            subtitle: Text(item.filename),
          ),
        ],
      ],
    );
  }

  /// 点击标签时优先按标签 id 进入搜索分支，未匹配到 id 时退化为文本查询。
  void _searchTag(BuildContext context, String tag) {
    final scope = AppScope.of(context);
    final match = scope.media.tags
        .where((entry) => entry.name == tag)
        .firstOrNull;
    scope.searchRequest.value = SearchRequest(label: tag, tagId: match?.id);
    context.goToDestination(AppDestination.search);
  }

  Future<void> _editNote(BuildContext context, MediaItem item) async {
    final note = await showNoteEditorDialog(context, item.note);
    if (note == null || !context.mounted) return;
    try {
      await controller.saveNote(note);
      if (!context.mounted) return;
      context.showLumaSnack('笔记已保存');
    } on Object catch (error) {
      if (!context.mounted) return;
      context.showLumaSnack('笔记保存失败：$error');
    }
  }
}
