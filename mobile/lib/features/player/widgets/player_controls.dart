import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../player_controller.dart';
import 'player_bottom_toolbar.dart';
import 'player_center_controls.dart';
import 'player_timeline.dart';
import 'player_top_bar.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onRotate,
  });

  final PlayerController controller;
  final VoidCallback onBack;
  final VoidCallback? onRotate;

  @override
  Widget build(BuildContext context) {
    if (controller.locked) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.all(LumaSpacing.md),
          child: FilledButton.icon(
            onPressed: () => controller.setLocked(false),
            icon: const Icon(Icons.lock_rounded),
            label: const Text('已锁定，点击解锁'),
          ),
        ),
      );
    }
    return Column(
      children: [
        PlayerTopBar(
          title: controller.item.title,
          resolution: controller.item.resolution,
          onBack: onBack,
        ),
        const Spacer(),
        PlayerCenterControls(controller: controller),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LumaSpacing.lg,
            0,
            LumaSpacing.lg,
            LumaSpacing.md,
          ),
          child: Column(
            children: [
              PlayerTimeline(controller: controller),
              PlayerBottomToolbar(controller: controller, onRotate: onRotate),
            ],
          ),
        ),
      ],
    );
  }
}
