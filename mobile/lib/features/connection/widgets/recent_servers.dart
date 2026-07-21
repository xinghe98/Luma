import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/layout/surface_card.dart';

typedef RecentServer = ({String name, String address, bool online});

class RecentServers extends StatelessWidget {
  const RecentServers({
    super.key,
    required this.enabled,
    required this.onSelect,
  });

  final bool enabled;
  final ValueChanged<RecentServer> onSelect;

  static const records = <RecentServer>[];

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: LumaSpacing.xs,
      children: [
        const SectionHeader(title: '最近连接', subtitle: '点击记录可快速填入地址'),
        ...records.map(
          (record) => SurfaceCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              onTap: enabled ? () => onSelect(record) : null,
              leading: Icon(
                Icons.storage_rounded,
                color: record.online
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              title: Text(record.name),
              subtitle: Text(record.address),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: record.online
                          ? LumaColors.success
                          : LumaColors.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
