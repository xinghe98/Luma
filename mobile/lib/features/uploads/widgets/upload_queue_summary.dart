// 上传页辅助展示：已选数量/字节摘要与来源加载骨架。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/states/skeleton.dart';

/// “已选 N 张 · 共 X MB”一行摘要；小屏随页面内边距换行。
class UploadQueueSummary extends StatelessWidget {
  const UploadQueueSummary({
    super.key,
    required this.count,
    required this.bytes,
  });

  final int count;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
      child: Text(
        '已选 $count 张 · 共 ${formatUploadBytes(bytes)}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 上传列表与摘要共用的字节格式化；与 tiles 保持一致精度。
String formatUploadBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    final value = bytes / (1024 * 1024);
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// 来源加载骨架：与选择器行高相近，不替换既有队列内容。
class UploadSourcesSkeleton extends StatelessWidget {
  const UploadSourcesSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SkeletonBox(height: 72),
      SizedBox(height: LumaSpacing.lg),
      SkeletonBox(height: 96),
      SizedBox(height: LumaSpacing.sm),
      SkeletonBox(height: 56),
    ],
  );
}
