// 选图失败/剔除项的提示条：附着在队列上方，不阻断页面操作。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 图片选择器抛错或全部所选项被剔除时展示的可关闭提示。
class PickErrorBanner extends StatelessWidget {
  const PickErrorBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LumaSpacing.sm,
          vertical: LumaSpacing.xxs,
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: LumaSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
            IconButton(
              tooltip: '知道了',
              onPressed: onDismiss,
              color: scheme.onErrorContainer,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
