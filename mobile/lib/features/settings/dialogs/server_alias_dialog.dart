import 'package:flutter/material.dart';

Future<String?> showServerAliasDialog(
  BuildContext context,
  String currentName,
) async {
  final controller = TextEditingController(text: currentName);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('服务器别名'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 80,
        decoration: const InputDecoration(labelText: '仅保存在此设备'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
