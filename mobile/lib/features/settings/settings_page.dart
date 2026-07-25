import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../app/app_scope.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../shared/layout/constrained_page_list.dart';
import '../../shared/layout/section_header.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import '../../shared/states/skeleton.dart';
import 'dialogs/about_luma_dialog.dart';
import 'dialogs/confirmation_dialog.dart';
import 'dialogs/server_alias_dialog.dart';
import 'widgets/application_settings_card.dart';
import 'widgets/server_settings_card.dart';
import '../../data/repositories/source_repository.dart';

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
      builder: (context, _) {
        final server = dependencies.session.server;
        if (server == null) {
          return Scaffold(
            appBar: AppBar(
              title: ScrollToTopAppBarTitle(title: '设置', controller: _scroll),
            ),
            body: const SettingsListSkeleton(items: 4),
          );
        }
        final canManageAccess =
            server.userRole == 'admin' &&
            server.capabilities.contains('users.manage') &&
            dependencies.sources != null;
        return Scaffold(
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
                  duration: LumaMotion.forContext(context, LumaMotion.fast),
                  switchInCurve: LumaMotion.standard,
                  switchOutCurve: LumaMotion.standard,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
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
            padding: LumaLayout.pagePadding(top: LumaSpacing.xs),
            children: [
              const SectionHeader(title: '当前服务器'),
              const SizedBox(height: LumaSpacing.sm),
              ServerSettingsCard(
                server: server,
                settings: settings,
                mediaCount: dependencies.media.catalogCount > 0
                    ? dependencies.media.catalogCount
                    : dependencies.media.items.length,
                onScanComplete: () async {
                  await dependencies.media.refresh();
                  if (!context.mounted) return;
                  context.showLumaSnack(
                    '扫描与影视资料匹配完成，发现 ${settings.scanDiscoveredCount} 个媒体文件',
                  );
                },
                onEditAlias: () => _editAlias(context),
                canScan: server.can('scans.manage'),
              ),
              const SizedBox(height: LumaSpacing.xl),
              const SectionHeader(title: '媒体库整理'),
              const SizedBox(height: LumaSpacing.sm),
              if (server.can('sources.manage') &&
                  dependencies.sources is MutableSourceRepository)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.folder_copy_outlined),
                  title: const Text('媒体源'),
                  subtitle: const Text('指定个人视频、图片、电影或电视剧目录'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.pushNamed<void>(AppRoute.librarySources),
                ),
              if (server.can('catalog.manage'))
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.rule_folder_outlined),
                  title: const Text('待整理文件'),
                  subtitle: const Text('修正无法自动识别的电影和剧集'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.pushNamed<void>(AppRoute.organization),
                ),
              if (canManageAccess) ...[
                const SizedBox(height: LumaSpacing.xl),
                const SectionHeader(title: '成员与访问'),
                const SizedBox(height: LumaSpacing.sm),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: const Text('成员与访问管理'),
                  subtitle: const Text('管理成员、媒体源授权和设备令牌'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      context.pushNamed<void>(AppRoute.accessManagement),
                ),
              ],
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
        );
      },
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
