import 'package:flutter/material.dart';

import '../../../app/controllers/settings_controller.dart';
import '../../../shared/layout/surface_card.dart';

class ApplicationSettingsCard extends StatelessWidget {
  const ApplicationSettingsCard({
    super.key,
    required this.settings,
    required this.onClearCache,
    required this.onAbout,
    required this.onDisconnect,
  });

  final SettingsController settings;
  final VoidCallback onClearCache;
  final VoidCallback onAbout;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.cached_rounded),
            title: const Text('缓存管理'),
            subtitle: Text(
              '${settings.cacheSizeMb.toStringAsFixed(0)} MB 缩略图缓存',
            ),
            trailing: TextButton(
              onPressed: settings.cacheSizeMb == 0 ? null : onClearCache,
              child: const Text('清理'),
            ),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('关于轻影'),
            subtitle: const Text('客户端版本 1.0.0'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onAbout,
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(
              Icons.link_off_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              '断开服务器',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: onDisconnect,
          ),
        ],
      ),
    );
  }
}
