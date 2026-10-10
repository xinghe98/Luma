import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_metadata.g.dart';
import '../../app/app_router.dart';
import '../../app/app_scope.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../shared/layout/adaptive_action_width.dart';
import '../../shared/layout/constrained_page_list.dart';
import '../../shared/layout/scroll_to_top_app_bar_title.dart';
import '../../shared/states/skeleton.dart';
import 'dialogs/about_luma_dialog.dart';
import 'dialogs/confirmation_dialog.dart';
import 'dialogs/server_alias_dialog.dart';
import 'widgets/server_settings_card.dart';
import 'widgets/settings_group.dart';
import 'widgets/theme_mode_button.dart';
import 'widgets/tv_settings_content.dart';
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
        if (dependencies.proxy != null) dependencies.proxy!,
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
        // TV 裁剪管理功能：观看为主，媒体源/成员访问/扫描留在普通端。
        final isTelevision = dependencies.deviceProfile.isTelevision;
        if (isTelevision) {
          return Scaffold(
            body: TvSettingsContent(
              scrollController: _scroll,
              onEditAlias: () => _editAlias(context),
              onClearCache: () => _clearCache(context),
              onAbout: () => showAboutLumaDialog(context),
              onDisconnect: () => _disconnect(context),
            ),
          );
        }
        final canManageAccess =
            server.userRole == 'admin' &&
            server.capabilities.contains('users.manage') &&
            dependencies.sources != null;
        final canScan = server.can('scans.manage');
        return Scaffold(
          appBar: AppBar(
            title: ScrollToTopAppBarTitle(title: '设置', controller: _scroll),
            actions: [
              ThemeModeButton(
                value: settings.themeMode,
                onChanged: settings.setThemeMode,
              ),
            ],
          ),
          body: ConstrainedPageList(
            scrollKey: const PageStorageKey('settings-scroll'),
            controller: _scroll,
            padding: LumaLayout.pagePadding(top: LumaSpacing.xs),
            children: [
              SettingsGroup(
                title: '服务器',
                children: [
                  ServerSettingsCard(
                    server: server,
                    settings: settings,
                    mediaCount: dependencies.media.catalogCount > 0
                        ? dependencies.media.catalogCount
                        : dependencies.media.items.length,
                    networkLabel: dependencies.proxy?.isActive == true
                        ? '网络：VMess · '
                              '${dependencies.proxy!.profile?.displayName ?? '已启动'}'
                        : '网络：直连',
                    onEditAlias: () => _editAlias(context),
                  ),
                ],
              ),
              SettingsGroup(
                title: '媒体库',
                children: [
                  ListTile(
                    leading: const Icon(Icons.sync_rounded),
                    title: Text(settings.scanStatusLabel),
                    subtitle: Text(
                      settings.scanStatusDetails,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: settings.isScanning
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: LumaSpacing.xs),
                              Text(
                                '${((settings.scanProgress ?? 0) * 100).round()}%',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          )
                        : FilledButton.tonal(
                            onPressed: canScan
                                ? () => settings.startScan(
                                    onComplete: () async {
                                      await dependencies.media.refresh();
                                      if (!context.mounted) return;
                                      context.showLumaSnack(
                                        '扫描与影视资料匹配完成，发现 '
                                        '${settings.scanDiscoveredCount} 个媒体文件',
                                      );
                                    },
                                  )
                                : null,
                            child: Text(
                              settings.scanError?.contains('中断') == true
                                  ? '重新扫描'
                                  : '手动扫描',
                            ),
                          ),
                  ),
                  if (server.can('sources.manage') &&
                      dependencies.sources is MutableSourceRepository)
                    ListTile(
                      leading: const Icon(Icons.folder_copy_outlined),
                      title: const Text('媒体源'),
                      subtitle: const Text('指定个人视频、图片、电影或电视剧目录'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          context.pushNamed<void>(AppRoute.librarySources),
                    ),
                ],
              ),
              if (canManageAccess)
                SettingsGroup(
                  title: '成员与访问',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.manage_accounts_outlined),
                      title: const Text('成员与访问管理'),
                      subtitle: const Text('管理成员、媒体源授权和设备令牌'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () =>
                          context.pushNamed<void>(AppRoute.accessManagement),
                    ),
                  ],
                ),
              SettingsGroup(
                title: '存储与关于',
                children: [
                  ListTile(
                    leading: const Icon(Icons.cached_rounded),
                    title: const Text('缓存管理'),
                    subtitle: Text(
                      '${settings.cacheSizeMb.toStringAsFixed(0)} MB 缩略图缓存',
                    ),
                    trailing: TextButton(
                      onPressed: settings.cacheSizeMb == 0
                          ? null
                          : () => _clearCache(context),
                      child: const Text('清理'),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text('关于${AppMetadata.displayName}'),
                    subtitle: Text('客户端版本 ${AppMetadata.version}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showAboutLumaDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: LumaSpacing.xl),
              AdaptiveActionWidth(
                maxWidth: LumaLayout.shortActionMaxWidth,
                child: OutlinedButton.icon(
                  onPressed: () => _disconnect(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('断开服务器'),
                  // 只用错误色文字，描边保持中性，避免整块红框过于醒目。
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
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
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final dependencies = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await dependencies.disconnect();
    } on Object {
      _showCredentialCleanupFailure(messenger, dependencies.disconnect);
    }
  }

  void _showCredentialCleanupFailure(
    ScaffoldMessengerState messenger,
    Future<void> Function() disconnect,
  ) {
    if (!messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('已断开服务器，但本机凭据未清除'),
          action: SnackBarAction(
            label: '重试',
            onPressed: () {
              unawaited(_retryCredentialCleanup(messenger, disconnect));
            },
          ),
        ),
      );
  }

  Future<void> _retryCredentialCleanup(
    ScaffoldMessengerState messenger,
    Future<void> Function() disconnect,
  ) async {
    try {
      await disconnect();
      if (!messenger.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('本机凭据已清除')));
    } on Object {
      _showCredentialCleanupFailure(messenger, disconnect);
    }
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
