import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/extensions.dart';
import '../../../core/theme.dart';
import '../../../shared/layout/surface_card.dart';

/// 首页扫描状态卡片，与设置页共用 [SettingsController] 的扫描状态。
class ScanStatusCard extends StatelessWidget {
  const ScanStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = AppScope.of(context);
    final settings = dependencies.settings;
    final media = dependencies.media;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, media]),
      builder: (context, _) {
        final scanning = settings.isScanning;
        final progress = settings.scanProgress ?? 0;
        final percent = (progress * 100).round();
        final count = media.items.length;
        final isProblem = settings.hasScanProblem;
        return SurfaceCard(
          padding: const EdgeInsets.symmetric(
            horizontal: LumaSpacing.md,
            vertical: LumaSpacing.sm,
          ),
          onTap: () => context.showLumaSnack(
            scanning
                ? '${settings.scanStatusLabel}：$percent%'
                : settings.scanStatusDetails,
          ),
          child: Row(
            children: [
              if (scanning)
                SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress > 0 ? progress : null,
                  ),
                )
              else
                Icon(
                  !isProblem
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  color: !isProblem
                      ? context.luma.success
                      : context.luma.warning,
                ),
              const SizedBox(width: LumaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.scanStatusLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: LumaSpacing.xxs),
                    Text(
                      scanning
                          ? '${settings.scanStatusDetails} · $percent%'
                          : settings.scanJobs.isEmpty
                          ? '媒体库共 $count 个项目 · 轻触查看状态'
                          : settings.scanStatusDetails,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (scanning)
                Text(
                  '$percent%',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
