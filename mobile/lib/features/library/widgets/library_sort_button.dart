// 媒体库排序菜单按钮：统一触控端与 TV 头部的排序入口。
// 组件不持有排序状态，选中值与变更回调都由调用方提供。
import 'package:flutter/material.dart';

import '../../../data/models/media_types.dart';

/// 以 MenuAnchor 呈现的排序选择按钮；[onChanged] 仅在选中值与当前不同语义下触发。
class LibrarySortButton extends StatelessWidget {
  /// 构建排序按钮；[value] 为当前生效的排序，菜单项会带上勾选态。
  /// [showDuration] 为 false 时（图片库）不提供「视频时长」排序。
  const LibrarySortButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.showDuration = true,
  });

  final MediaSort value;
  final ValueChanged<MediaSort> onChanged;
  final bool showDuration;

  /// 排序条件的展示文案；与旧的弹层菜单保持一致。
  static String labelOf(MediaSort sort) => switch (sort) {
    MediaSort.newest => '最新添加',
    MediaSort.title => '标题名称',
    MediaSort.duration => '视频时长',
  };

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final sort in MediaSort.values)
          if (showDuration || sort != MediaSort.duration)
            MenuItemButton(
              onPressed: () => onChanged(sort),
              trailingIcon: sort == value
                  ? const Icon(Icons.check_rounded)
                  : null,
              child: Text(labelOf(sort)),
            ),
      ],
      builder: (context, menuController, child) => TextButton.icon(
        onPressed: () => menuController.isOpen
            ? menuController.close()
            : menuController.open(),
        icon: const Icon(Icons.swap_vert_rounded),
        label: Text(labelOf(value)),
      ),
    );
  }
}
