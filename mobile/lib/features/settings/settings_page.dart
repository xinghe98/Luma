import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../shared/layout/constrained_page_list.dart';
import '../../shared/layout/section_header.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import 'dialogs/about_luma_dialog.dart';
import 'dialogs/confirmation_dialog.dart';
import 'dialogs/server_alias_dialog.dart';
import 'widgets/application_settings_card.dart';
import 'widgets/server_settings_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = AppScope.of(context);
    final settings = dependencies.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([
        settings,
        dependencies.media,
        dependencies.session,
      ]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: ScrollToTopAppBarTitle(title: '设置', controller: _scroll),
          actions: [
            IconButton(
              tooltip: settings.themeMode == ThemeMode.dark
                  ? '切换到浅色模式'
                  : '切换到深色模式',
              onPressed: () => settings.setThemeMode(
                settings.themeMode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
              ),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  key: ValueKey(settings.themeMode),
                  settings.themeMode == ThemeMode.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
            ),
          ],
        ),
        body: ConstrainedPageList(
          scrollKey: const PageStorageKey('settings-scroll'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            const SectionHeader(title: '当前服务器'),
            const SizedBox(height: LumaSpacing.sm),
            ServerSettingsCard(
              server: dependencies.session.server!,
              settings: settings,
              mediaCount: dependencies.media.catalogCount > 0
                  ? dependencies.media.catalogCount
                  : dependencies.media.items.length,
              onScanComplete: () async {
                await dependencies.media.refresh();
                await dependencies.media.refreshCatalogCount();
                if (!context.mounted) return;
                context.showLumaSnack(
                  '扫描完成，发现 ${settings.scanDiscoveredCount} 个媒体文件',
                );
              },
              onEditAlias: () => _editAlias(context),
            ),
            const SizedBox(height: LumaSpacing.xl),
            const SectionHeader(title: '存储与应用'),
            const SizedBox(height: LumaSpacing.sm),
            ApplicationSettingsCard(
              settings: settings,
              onClearCache: () => _clearCache(context),
              onAbout: () => showAboutLumaDialog(context),
              onDisconnect: () => _disconnect(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: '清理缓存？',
      message: '仅清理本机内存中的缩略图缓存，不影响服务器文件。',
      confirmLabel: '清理',
    );
    if (!confirmed || !context.mounted) return;
    AppScope.of(context).settings.clearCache();
    context.showLumaSnack('缓存已清理');
  }

  Future<void> _disconnect(BuildContext context) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: '断开服务器？',
      message: '断开后将返回连接页，本次会话中的操作会被重置。',
      confirmLabel: '断开',
    );
    if (!confirmed || !context.mounted) return;
    await AppScope.of(context).disconnect();
  }

  Future<void> _editAlias(BuildContext context) async {
    final dependencies = AppScope.of(context);
    final server = dependencies.session.server;
    if (server == null) return;
    final alias = await showServerAliasDialog(context, server.name);
    if (alias == null || !context.mounted) return;
    await dependencies.updateServerAlias(alias);
  }
}
