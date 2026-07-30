import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 打开服务器别名编辑框；取消返回 null，恢复默认返回空字符串。
Future<String?> showServerAliasDialog(
  BuildContext context,
  String currentName,
) => showDialog<String>(
  context: context,
  // 编辑取消后立即移除遮罩和阴影，避免键盘收起时留下退场残影。
  animationStyle: AnimationStyle.noAnimation,
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
    scrollable: true,
    title: const Text('服务器别名'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: '仅保存在此设备'),
    ),
    actionsAlignment: MainAxisAlignment.end,
    actionsOverflowAlignment: OverflowBarAlignment.end,
    actionsOverflowButtonSpacing: LumaSpacing.xs,
    actionsPadding: const EdgeInsets.fromLTRB(
      LumaSpacing.xs,
      0,
      LumaSpacing.xs,
      LumaSpacing.xs,
    ),
    buttonPadding: EdgeInsets.zero,
    actions: [
      TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size.square(LumaLayout.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.xxs),
        ),
        onPressed: () => Navigator.pop(context, ''),
        child: const Text('恢复默认'),
      ),
      TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size.square(LumaLayout.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.xxs),
        ),
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.square(LumaLayout.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.xxs),
        ),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('保存'),
      ),
    ],
  );
}
