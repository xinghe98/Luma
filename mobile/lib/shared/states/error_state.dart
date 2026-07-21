import 'package:flutter/material.dart';

import 'empty_state.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: '媒体库暂时不可用',
      message: '没有成功读取服务器内容，请稍后重试。',
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重新加载'),
      ),
    );
  }
}
