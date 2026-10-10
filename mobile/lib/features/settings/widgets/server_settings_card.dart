// 服务器卡片内容：名称、地址、版本、网络通道与指标行，由设置页的 SettingsGroup 提供卡片容器。
// 自身无状态；扫描操作入口在「媒体库」分组，不在此卡片内。
import 'package:flutter/material.dart';

import '../../../app/controllers/settings_controller.dart';
import '../../../core/theme.dart';
import '../../../data/models/server_profile.dart';

/// 「服务器」分组内的会话摘要；外层卡片与分组标题由 SettingsGroup 渲染。
class ServerSettingsCard extends StatelessWidget {
  const ServerSettingsCard({
    super.key,
    required this.server,
    required this.settings,
    required this.mediaCount,
    required this.networkLabel,
    required this.onEditAlias,
  });

  final ServerProfile server;
  final SettingsController settings;
  final int mediaCount;

  /// 当前会话的网络通道描述，形如「网络：直连」。
  final String networkLabel;
  final VoidCallback onEditAlias;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(LumaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Semantics(
                          label: '已连接',
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: context.luma.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: LumaSpacing.xs),
                        Flexible(
                          child: Text(
                            server.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: LumaSpacing.xxs),
                    Text(
                      server.address,
                      style: theme.textTheme.bodySmall,
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                      ),
                    ),
                    Text(
                      networkLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '重命名',
                onPressed: onEditAlias,
                icon: const Icon(Icons.edit_rounded),
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
        Text(value, style: Theme.of(context).textTheme.titleLarge),
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
