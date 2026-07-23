import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';

void showAboutLumaDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const BrandMark(
          variant: BrandMarkVariant.horizontal,
          height: 32,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '轻影是一款连接家庭服务器的私有影像管理播放器。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: LumaSpacing.sm),
            Text(
              '媒体数据由已连接的轻影服务器提供。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}
