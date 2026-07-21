import 'package:flutter/material.dart';

Future<String?> showNoteEditorDialog(BuildContext context, String note) async {
  final controller = TextEditingController(text: note);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('编辑笔记'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(hintText: '写下关于这段影像的想法'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
