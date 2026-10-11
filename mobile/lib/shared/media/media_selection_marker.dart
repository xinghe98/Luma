// 图片库卡片共用的勾选标记，以独立底色隔开封面；选中状态和点击由外层卡片管理。
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 封面左上角的勾选指示器；实心底色与明暗双描边保证不同封面上的可见性。
class MediaSelectionMarker extends StatelessWidget {
  /// 显示卡片的选中状态，点击与键盘操作继续由外层卡片处理。
  const MediaSelectionMarker({super.key, required this.selected});

  /// 当前项是否已选中；未选中显示深色空圈，选中显示主色底与高对比勾号。
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = context.luma;
    return Container(
      width: LumaIconSize.prominent,
      height: LumaIconSize.prominent,
      padding: const EdgeInsets.all(LumaStroke.focused),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: extras.playerInk,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? scheme.primary : extras.playerInk,
          border: Border.all(
            color: extras.onPlayerInk,
            width: LumaStroke.focused,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: LumaIconSize.status,
                color: scheme.onPrimary,
              )
            : null,
      ),
    );
  }
}
