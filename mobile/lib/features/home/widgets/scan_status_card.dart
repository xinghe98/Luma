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
        final scheme = Theme.of(context).colorScheme;
        final scanning = settings.isScanning;
        final progress = settings.scanProgress ?? 0;
        final percent = (progress * 100).round();
        final count = media.items.length;
        final isProblem = settings.hasScanProblem;
        return SurfaceCard(
          color: scheme.primary,
          radius: LumaRadii.large,
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
                    color: scheme.onPrimary,
                    backgroundColor: scheme.onPrimary.withValues(alpha: 0.24),
                  ),
                )
              else
                Icon(
                  !isProblem
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  color: !isProblem
                      ? scheme.onPrimary
                      : context.luma.warning,
                ),
              const SizedBox(width: LumaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.scanStatusLabel,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: scheme.onPrimary),
                    ),
                    const SizedBox(height: LumaSpacing.xxs),
                    Text(
                      scanning
                          ? '${settings.scanStatusDetails} · $percent%'
                          : settings.scanJobs.isEmpty
                          ? '媒体库共 $count 个项目 · 轻触查看状态'
                          : settings.scanStatusDetails,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              if (scanning)
                Text(
                  '$percent%',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimary,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
