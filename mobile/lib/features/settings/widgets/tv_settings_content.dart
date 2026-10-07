// TV 设置将会话摘要与纵向动作分栏，复用设置页的业务回调与 AppScope 状态。
// 每行拥有稳定焦点身份，集合在方向键移动时滚动到实际行高；卸载时释放行节点。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_metadata.g.dart';
import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../shared/interaction/luma_focusable_surface.dart';
import '../../../shared/interaction/tv_focus_collection.dart';
import '../../../shared/interaction/tv_key_bindings.dart';

class TvSettingsContent extends StatefulWidget {
  const TvSettingsContent({
    super.key,
    required this.scrollController,
    required this.onEditAlias,
    required this.onClearCache,
    required this.onAbout,
    required this.onDisconnect,
  });

  final ScrollController scrollController;
  final VoidCallback onEditAlias;
  final VoidCallback onClearCache;
  final VoidCallback onAbout;
  final VoidCallback onDisconnect;

  @override
  State<TvSettingsContent> createState() => _TvSettingsContentState();
}

class _TvSettingsContentState extends State<TvSettingsContent> {
  static const _ids = ['theme', 'alias', 'cache', 'about', 'disconnect'];
  final _rowKeys = List.generate(_ids.length, (_) => GlobalKey());

  Future<void> _reveal(int index) async {
    final target = _rowKeys[index].currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      duration: LumaMotion.forContext(context, LumaMotion.fast),
      curve: Curves.easeOutQuart,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = AppScope.of(context);
    final settings = dependencies.settings;
    final server = dependencies.session.server!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final mediaCount = dependencies.media.catalogCount > 0
        ? dependencies.media.catalogCount
        : dependencies.media.items.length;
    final summary = Column(
      key: const ValueKey('tv-settings-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: LumaSpacing.sm),
            Text('已连接', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: LumaSpacing.lg),
        Text(server.name, style: theme.textTheme.titleLarge),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          server.address,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: LumaSpacing.lg),
        Text(
          '$mediaCount 个媒体项目 · ${server.sourceCount} 个媒体源',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          '扫描状态：${settings.scanStatusLabel}',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          dependencies.proxy?.isActive == true
              ? '网络：VMess · ${dependencies.proxy!.profile?.displayName ?? '已启动'}'
              : '网络：直连',
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        if (server.version != null) ...[
          const SizedBox(height: LumaSpacing.sm),
          Text(
            '服务器 ${server.version}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ],
    );
    final actions = TvFocusCollection(
      itemIds: _ids,
      axis: Axis.vertical,
      columns: 1,
      revealIndex: _reveal,
      child: Column(
        key: const ValueKey('tv-settings-actions'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _group(context, '观看与连接'),
          _row(
            context,
            index: 0,
            title: '显示主题',
            subtitle: settings.themeMode == ThemeMode.light ? '浅色模式' : '深色模式',
            icon: Icons.contrast_rounded,
            onActivate: () => settings.setThemeMode(
              settings.themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark,
            ),
          ),
          _row(
            context,
            index: 1,
            title: '服务器别名',
            subtitle: '仅在此设备显示',
            icon: Icons.edit_outlined,
            onActivate: widget.onEditAlias,
          ),
          const SizedBox(height: LumaSpacing.lg),
          _group(context, '存储与应用'),
          _row(
            context,
            index: 2,
            title: '缓存管理',
            subtitle: '${settings.cacheSizeMb.toStringAsFixed(0)} MB 缩略图缓存',
            icon: Icons.cached_rounded,
            onActivate: widget.onClearCache,
          ),
          _row(
            context,
            index: 3,
            title: '关于${AppMetadata.displayName}',
            subtitle: '客户端版本 ${AppMetadata.version}',
            icon: Icons.info_outline_rounded,
            onActivate: widget.onAbout,
          ),
          const SizedBox(height: LumaSpacing.lg),
          _group(context, '当前会话'),
          _row(
            context,
            index: 4,
            title: '断开服务器',
            subtitle: '返回连接页',
            icon: Icons.link_off_rounded,
            onActivate: widget.onDisconnect,
            destructive: true,
          ),
        ],
      ),
    );
    return TvKeyBindings(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 760 &&
              MediaQuery.textScalerOf(context).scale(18) <= 27;
          return SingleChildScrollView(
            key: const PageStorageKey('settings-scroll'),
            controller: widget.scrollController,
            padding: const EdgeInsets.all(LumaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('设置', style: theme.textTheme.headlineLarge),
                const SizedBox(height: LumaSpacing.xs),
                Text(
                  '管理这台电视的观看体验',
                  style: theme.textTheme.bodyLarge?.copyWith(color: muted),
                ),
                const SizedBox(height: LumaSpacing.xl),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: summary),
                      const SizedBox(width: LumaSpacing.xl),
                      Expanded(flex: 3, child: actions),
                    ],
                  )
                else ...[
                  summary,
                  const SizedBox(height: LumaSpacing.xl),
                  actions,
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _group(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(
      bottom: LumaSpacing.sm,
      left: LumaSpacing.md,
    ),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _row(
    BuildContext context, {
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onActivate,
    bool destructive = false,
  }) {
    final theme = Theme.of(context);
    final color = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return Padding(
      key: _rowKeys[index],
      padding: const EdgeInsets.only(bottom: LumaSpacing.xs),
      child: LumaFocusableSurface(
        key: ValueKey('tv-settings-${_ids[index]}'),
        focusId: _ids[index],
        autofocus: index == 0,
        onFocusChange: (focused) {
          if (!focused) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_reveal(index));
          });
        },
        label: '$title，$subtitle',
        onActivate: onActivate,
        borderRadius: BorderRadius.circular(LumaRadii.small),
        focusBorderWidth: LumaTvLayout.focusStroke,
        contentPadding: const EdgeInsets.all(LumaSpacing.md),
        child: Builder(
          builder: (context) {
            final focused = LumaFocusMark.focusedOf(context);
            final scheme = theme.colorScheme;
            final titleColor = destructive
                ? color
                : focused
                ? scheme.onInverseSurface
                : scheme.onSurface;
            final subtitleColor = focused
                ? scheme.onInverseSurface.withValues(alpha: 0.72)
                : scheme.onSurfaceVariant;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: focused ? scheme.inverseSurface : Colors.transparent,
                borderRadius: BorderRadius.circular(LumaRadii.small),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: LumaTvLayout.controlMinHeight,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: destructive ? color : titleColor,
                      size: 28,
                    ),
                    const SizedBox(width: LumaSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: destructive ? color : titleColor,
                            ),
                          ),
                          const SizedBox(height: LumaSpacing.xxs),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: LumaSpacing.sm),
                    Icon(Icons.chevron_right_rounded, color: titleColor),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
