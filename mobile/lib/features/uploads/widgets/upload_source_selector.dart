// 上传目标来源选择器：自适应窄屏 bottom sheet / 宽屏 dialog，
// 复用 single_choice_sheet 的选择交互，只负责“选一个已启用来源”。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_source.dart';
import '../../../shared/widgets/single_choice_sheet.dart';

/// 展示已选来源并提供修改入口；[enabled] 为 false 时不允许打开选择。
/// 未选择时显示提示文案；已选时显示来源名，附赠“上次使用”可选标记。
class UploadSourceSelector extends StatelessWidget {
  const UploadSourceSelector({
    super.key,
    required this.sources,
    required this.selectedSourceId,
    required this.onSelected,
    this.enabled = true,
    this.lastUsedSourceId,
  });

  /// 当前会话可上传的来源列表；只应包含已启用项。
  final List<Source> sources;
  final String? selectedSourceId;
  final ValueChanged<String> onSelected;

  /// 是否允许打开选择；上传进行中或列表加载中置 false。
  final bool enabled;

  /// 该身份最近一次成功写入的来源 id，用于在列表中标记。
  final String? lastUsedSourceId;

  /// 打开自适应选择层；返回用户确认的来源 id 或 null（取消）。
  Future<void> _openPicker(BuildContext context) async {
    final picked = await showSingleChoiceSheet<String>(
      context,
      title: '保存到媒体源',
      supportingText: '图片会保存到所选来源的根目录。',
      selectedValue: selectedSourceId,
      choices: [
        for (final source in sources)
          BottomSheetChoice(
            value: source.id,
            label: source.name,
            icon: Icons.photo_library_outlined,
            description: source.id == lastUsedSourceId ? '上次使用' : null,
          ),
      ],
    );
    if (picked != null && context.mounted) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _resolveSelected();
    return SurfaceContainer(
      child: InkWell(
        onTap: enabled && sources.isNotEmpty
            ? () => _openPicker(context)
            : null,
        borderRadius: BorderRadius.circular(LumaRadii.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LumaSpacing.md,
            vertical: LumaSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.drive_folder_upload_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: LumaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '保存到',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: LumaSpacing.xxs),
                    Text(
                      selected?.name ?? '选择保存位置',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Source? _resolveSelected() {
    final id = selectedSourceId;
    if (id == null) return null;
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }
}

/// 与本页一致的浅色表面容器；圆角与边框沿用卡片规范。
class SurfaceContainer extends StatelessWidget {
  const SurfaceContainer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumaRadii.medium),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}
