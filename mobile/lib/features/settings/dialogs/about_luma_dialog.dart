import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../app/app_metadata.g.dart';
import '../../../shared/branding/brand_mark.dart';

/// 显示应用说明；关闭弹窗不会修改任何设置。
void showAboutLumaDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    animationStyle: AnimationStyle.noAnimation,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        scrollable: true,
        title: const BrandMark(
          variant: BrandMarkVariant.horizontal,
          height: 32,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppMetadata.displayName}是一款连接家庭服务器的私有影像管理播放器。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: LumaSpacing.sm),
            Text(
              '媒体数据由已连接的${AppMetadata.displayName}服务器提供。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: LumaSpacing.sm),
            Text(
              '版本 ${AppMetadata.version} · ${AppMetadata.companyName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (AppMetadata.authorName.isNotEmpty) ...[
              const SizedBox(height: LumaSpacing.sm),
              Text(
                '作者：${AppMetadata.authorName}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: LumaSpacing.sm),
            Text(
              '界面字体采用 MiSans，版权归小米科技有限责任公司所有。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: LumaSpacing.sm),
            Text(
              'Xray-core v26.7.28 源码：'
              'https://github.com/XTLS/Xray-core/tree/v26.7.28',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              showLicensePage(
                context: context,
                applicationName: AppMetadata.displayName,
                applicationVersion: AppMetadata.version,
                applicationLegalese: 'libXray v26.7.28 · Xray-core v26.7.28',
              );
            },
            child: const Text('开源许可'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
}
