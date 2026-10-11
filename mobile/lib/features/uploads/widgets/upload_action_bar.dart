// 上传页底部操作区：主操作自适应宽度，按钮随队列状态切换；
// 不做全屏 spinner，上传中仅在条目与按钮上反馈进度。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/layout/adaptive_action_width.dart';
import '../image_upload_controller.dart';

class UploadActionBar extends StatelessWidget {
  const UploadActionBar({
    super.key,
    required this.controller,
    required this.onPick,
    required this.onStart,
    required this.onRetry,
    required this.onDone,
    this.canPick = true,
  });

  /// 媒体源未就绪/为空时置 false，选图按钮禁用（无目录不开 picker）。
  final bool canPick;

  final ImageUploadController controller;
  final VoidCallback onPick;
  final VoidCallback onStart;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final uploading = controller.uploading;
    final hasItems = controller.selectedCount > 0;
    final hasPending = controller.hasPendingItems;
    final hasRetryable = controller.hasRetryableFailure;
    final hasSuccess = controller.hasSuccessfulUpload;
    final invalidated = controller.sessionInvalidated;

    Widget primary;
    if (invalidated) {
      primary = FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.lock_outline_rounded),
        label: const Text('会话已切换'),
      );
    } else if (uploading) {
      primary = FilledButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('正在上传'),
      );
    } else if (hasRetryable && !hasPending) {
      primary = FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重试失败项'),
      );
    } else if (hasPending) {
      primary = FilledButton.icon(
        onPressed: controller.selectedSourceId == null ? null : onStart,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text('开始上传'),
      );
    } else if (hasSuccess) {
      primary = FilledButton.icon(
        onPressed: onDone,
        icon: const Icon(Icons.check_rounded),
        label: const Text('完成'),
      );
    } else {
      primary = FilledButton.icon(
        onPressed: canPick ? onPick : null,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('选择图片'),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(
        LumaLayout.pagePaddingH,
        LumaSpacing.sm,
        LumaLayout.pagePaddingH,
        LumaSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: AdaptiveActionWidth(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (hasItems && !uploading && !invalidated) ...[
                OutlinedButton.icon(
                  onPressed: canPick ? onPick : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('再选'),
                ),
                const SizedBox(width: LumaSpacing.sm),
              ],
              Flexible(child: primary),
            ],
          ),
        ),
      ),
    );
  }
}
