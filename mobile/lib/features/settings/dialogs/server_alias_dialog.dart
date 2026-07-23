import 'package:flutter/material.dart';

Future<String?> showServerAliasDialog(
  BuildContext context,
  String currentName,
) => showDialog<String>(
  context: context,
  builder: (_) => _ServerAliasDialog(currentName: currentName),
);

class _ServerAliasDialog extends StatefulWidget {
  const _ServerAliasDialog({required this.currentName});

  final String currentName;

  @override
  State<_ServerAliasDialog> createState() => _ServerAliasDialogState();
}

class _ServerAliasDialogState extends State<_ServerAliasDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('服务器别名'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: '仅保存在此设备'),
    ),
    actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    actions: [
      SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('恢复默认'),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: () => Navigator.pop(context, _controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    ],
  );
}
