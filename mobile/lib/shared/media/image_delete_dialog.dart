// 图片永久删除的共用确认入口，供图库多选和预览工具栏调用。
// 这里只收集用户确认，不发请求；关闭后由调用方校验会话并执行删除。
import 'package:flutter/material.dart';

/// 确认永久删除指定数量的服务器原图；取消、返回或 Escape 均返回 false。
Future<bool> confirmImageDeletion(
  BuildContext context, {
  required int count,
}) async {
  if (count <= 0) return false;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(count == 1 ? '删除这张图片？' : '删除 $count 张图片？'),
          content: const Text('将永久删除服务器上的原文件，所有用户都将无法再查看。此操作无法撤销。'),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('永久删除'),
            ),
          ],
        ),
      ) ??
      false;
}
