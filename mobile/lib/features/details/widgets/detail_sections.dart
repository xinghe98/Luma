import 'package:flutter/material.dart';

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
          children: item.tags
              .map(
                (tag) => ActionChip(
                  label: Text(tag),
                  onPressed: () => context.showLumaSnack('可在搜索页筛选“$tag”标签'),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: LumaSpacing.xxs,
            ),
            leading: const Icon(Icons.storage_rounded),
            title: const Text('媒体源'),
            subtitle: Text(
              item.sourceName.isEmpty ? item.sourceId : item.sourceName,
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: LumaSpacing.xxs,
            ),
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: const Text('文件名'),
            subtitle: Text(item.filename),
          ),
        ],
      ],
    );
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
