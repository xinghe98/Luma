import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../details_controller.dart';
import 'detail_actions.dart';
import 'detail_sections.dart';
import 'media_metadata.dart';
import 'playback_progress.dart';

class DetailInformation extends StatelessWidget {
  const DetailInformation({super.key, required this.controller});

  final DetailsController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.item;
    if (item == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: LumaSpacing.lg),
        DetailActions(controller: controller),
        PlaybackProgress(item: item),
        const SizedBox(height: LumaSpacing.xl),
        MediaMetadata(item: item),
        const SizedBox(height: LumaSpacing.xl),
        DetailSections(controller: controller),
      ],
    );
  }
}
