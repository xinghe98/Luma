// 上传队列条目与缩略图：本地缩略图经 Image.file 走系统缓存
// （bounded by imageCache），条目展示状态/进度/错误与重试入口。
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../image_upload_controller.dart';
import 'upload_queue_summary.dart';

/// 队列条目：本地缩略图 + 文件名/字节数 + 状态与操作。
/// [onRemove] 为 null 时隐藏移除按钮（上传中或已完成）。
class UploadQueueTile extends StatelessWidget {
  const UploadQueueTile({super.key, required this.entry, this.onRemove});

  final ImageUploadEntry entry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LumaSpacing.md,
        vertical: LumaSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _LocalThumbnail(path: entry.image.path),
          const SizedBox(width: LumaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.status == ImageUploadStatus.success &&
                          entry.result != null
                      ? entry.result!.filename
                      : entry.image.filename,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: LumaSpacing.xxs),
                Text(
                  _subtitle(context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _subtitleColor(scheme),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: LumaSpacing.sm),
          _trailing(context),
        ],
      ),
    );
  }

  String _subtitle(BuildContext context) {
    switch (entry.status) {
      case ImageUploadStatus.pending:
        return entry.errorMessage ?? formatUploadBytes(entry.image.contentLength);
      case ImageUploadStatus.uploading:
        final total = entry.image.contentLength;
        final sent = entry.sentBytes;
        final percent = total > 0 ? (sent / total * 100).clamp(0, 100) : 0;
        return '上传中 ${formatUploadBytes(sent)} / ${formatUploadBytes(total)} · ${percent.toStringAsFixed(0)}%';
      case ImageUploadStatus.success:
        return '已上传';
      case ImageUploadStatus.failed:
        return entry.errorMessage ?? '上传失败';
    }
  }

  Color? _subtitleColor(ColorScheme scheme) => switch (entry.status) {
    ImageUploadStatus.failed => scheme.error,
    ImageUploadStatus.success => scheme.primary,
    _ => scheme.onSurfaceVariant,
  };

  Widget _trailing(BuildContext context) {
    switch (entry.status) {
      case ImageUploadStatus.uploading:
        final total = entry.image.contentLength;
        // onSendProgress 含 multipart 开销，须 clamp 防止指示器 value>1。
        final value = total > 0
            ? (entry.sentBytes / total).clamp(0.0, 1.0)
            : null;
        return SizedBox(
          width: LumaLayout.minTapTarget,
          height: LumaLayout.minTapTarget,
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, value: value),
            ),
          ),
        );
      case ImageUploadStatus.success:
        return _StatusIcon(
          icon: Icons.check_circle_rounded,
          color: Theme.of(context).colorScheme.primary,
          tooltip: '已上传',
        );
      case ImageUploadStatus.failed:
        return _StatusIcon(
          icon: Icons.error_outline_rounded,
          color: Theme.of(context).colorScheme.error,
          tooltip: entry.retryable ? '失败，可在下方重试' : '失败',
        );
      case ImageUploadStatus.pending:
        return IconButton(
          tooltip: '移除',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded),
        );
    }
  }
}

/// 本地文件缩略图：ResizeImage 按 56dp×dpr 上限解码，
/// 不把原尺寸字节留进 imageCache；解码失败回退占位。
class _LocalThumbnail extends StatelessWidget {
  const _LocalThumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 56dp 目标尺寸按当前像素比换算解码上限，只限宽保持原始比例。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (56 * dpr).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(LumaRadii.small),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Image(
          image: ResizeImage(
            FileImage(File(path)),
            width: cacheWidth,
            policy: ResizeImagePolicy.fit,
          ),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(scheme),
          frameBuilder: (_, child, frame, wasSync) {
            if (wasSync || frame != null) return child;
            return _placeholder(scheme);
          },
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) => ColoredBox(
    color: scheme.surfaceContainerHighest,
    child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
  );
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: LumaLayout.minTapTarget,
    height: LumaLayout.minTapTarget,
    child: Tooltip(
      message: tooltip,
      child: Icon(icon, color: color, size: 26),
    ),
  );
}
