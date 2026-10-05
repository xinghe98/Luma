import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../details_controller.dart';
import 'detail_actions.dart';
import 'detail_sections.dart';
import 'media_metadata.dart';
import 'playback_progress.dart';
import 'tv_scrollable_detail_region.dart';

class DetailInformation extends StatelessWidget {
  const DetailInformation({
    super.key,
    required this.controller,
    this.television = false,
    this.autofocusPrimary = false,
    this.playFocusNode,
  });

  final DetailsController controller;

  /// TV：收藏按钮带文字、隐藏笔记编辑；普通端保持默认。
  final bool television;

  /// TV 首次有效内容聚焦主播放。
  final bool autofocusPrimary;

  /// 主播放按钮焦点节点（TV 首帧聚焦用）。
  final FocusNode? playFocusNode;

  @override
  Widget build(BuildContext context) {
    final item = controller.item;
    if (item == null) return const SizedBox.shrink();
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MediaMetadata(item: item),
        const SizedBox(height: LumaSpacing.xl),
        DetailSections(controller: controller, allowEditing: !television),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: LumaSpacing.lg),
        DetailActions(
          controller: controller,
          television: television,
          autofocusPrimary: autofocusPrimary,
          connectFocusNode: playFocusNode,
        ),
        PlaybackProgress(item: item),
        const SizedBox(height: LumaSpacing.xl),
        // 只读资料独立获焦，播放与收藏始终保持正常方向遍历。
        if (television)
          TvScrollableDetailRegion(child: information)
        else
          information,
      ],
    );
  }
}
