import 'package:flutter/material.dart';

import '../../../app/controllers/settings_controller.dart';
import '../../../core/theme.dart';
import '../../../data/models/server_profile.dart';
import '../../../shared/layout/surface_card.dart';

class ServerSettingsCard extends StatelessWidget {
  const ServerSettingsCard({
    super.key,
    required this.server,
    required this.settings,
    required this.mediaCount,
    required this.onScanComplete,
    required this.onEditAlias,
    this.canScan = true,
  });

  final ServerProfile server;
  final SettingsController settings;
  final int mediaCount;
  final VoidCallback onScanComplete;
  final VoidCallback onEditAlias;
  final bool canScan;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(LumaRadii.small),
                ),
                child: const Icon(Icons.dns_rounded),
              ),
              const SizedBox(width: LumaSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            server.name,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: '编辑本地别名',
                          visualDensity: VisualDensity.compact,
                          onPressed: onEditAlias,
                          icon: const Icon(Icons.edit_outlined, size: 17),
                        ),
                      ],
                    ),
                    Text(
                      server.address,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      [
                        if (server.platform != null)
                          '${server.platform} ${server.architecture ?? ''}'
                              .trim(),
                        if (server.database != null)
                          'Database: ${server.database}',
                        if (server.version != null)
                          'Version: ${server.version}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Chip(
                avatar: Icon(Icons.check_circle, size: 16),
                label: Text('已连接'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: LumaSpacing.sm),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              _Metric(label: '媒体源', value: '${server.sourceCount}'),
              _Metric(label: '媒体项目', value: '$mediaCount'),
              _Metric(label: '扫描状态', value: settings.scanStatusLabel),
            ],
          ),
          const SizedBox(height: LumaSpacing.sm),
          Text(
            settings.scanStatusDetails,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: settings.hasScanProblem
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (settings.scanProgress != null) ...[
            const SizedBox(height: LumaSpacing.md),
            LinearProgressIndicator(
              value: settings.scanProgress,
              borderRadius: BorderRadius.circular(LumaRadii.badge),
            ),
          ],
          const SizedBox(height: LumaSpacing.md),
          if (canScan)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: settings.isScanning
                    ? null
                    : () => settings.startScan(onComplete: onScanComplete),
                icon: const Icon(Icons.sync_rounded),
                label: Text(
                  settings.isScanning
                      ? settings.scanStatusLabel
                      : settings.scanError?.contains('中断') == true
                      ? '重新扫描'
                      : '手动扫描',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
