// 通用错误状态支持完整页面和保留旧内容时的紧凑提示。
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'empty_state.dart';

/// 展示可配置的错误说明并触发重试，不负责管理请求状态。
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.onRetry,
    this.title = '媒体库暂时不可用',
    this.message = '没有成功读取服务器内容，请稍后重试。',
    this.retryLabel = '重新加载',
    this.icon = Icons.cloud_off_outlined,
    this.compact = false,
  });

  final VoidCallback onRetry;
  final String title;
  final String message;
  final String retryLabel;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LumaLayout.pagePaddingH,
          vertical: LumaSpacing.xs,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(LumaRadii.medium),
          ),
          child: Padding(
            padding: const EdgeInsets.all(LumaSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: scheme.onErrorContainer),
                const SizedBox(width: LumaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: LumaSpacing.xxs),
                      Text(
                        message,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: retryLabel,
                  onPressed: onRetry,
                  color: scheme.onErrorContainer,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return EmptyState(
      icon: icon,
      title: title,
      message: message,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(retryLabel),
      ),
    );
  }
}
