import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/theme.dart';
import '../../../data/models/api_access.dart';
import '../../../data/repositories/access_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../shared/layout/adaptive_action_width.dart';
import '../../../shared/layout/constrained_page_list.dart';
import '../../../shared/states/empty_state.dart';
import '../../../shared/states/skeleton.dart';

class AccessManagementPage extends StatefulWidget {
  const AccessManagementPage({
    super.key,
    required this.access,
    required this.sources,
  });

  final AccessRepository access;
  final SourceRepository sources;

  @override
  State<AccessManagementPage> createState() => _AccessManagementPageState();
}

class _AccessManagementPageState extends State<AccessManagementPage> {
  List<AccessUser>? _users;
  Object? _error;
  int _loadGeneration = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('成员与访问管理'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _body(),
  );

  Widget _body() {
    final users = _users;
    if (users == null) {
      if (_error != null) {
        return EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '无法读取成员',
          message: '请检查服务器连接后重试。',
          action: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载'),
          ),
        );
      }
      return const SettingsListSkeleton(items: 3, showAction: true);
    }
    return ConstrainedPageList(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      children: [
        Text(
          '管理家庭成员可访问的媒体源和设备令牌。在线表示最近 2 分钟内有服务端访问，页面每 30 秒自动刷新。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: LumaSpacing.lg),
        AdaptiveActionWidth(
          maxWidth: 240,
          child: FilledButton.icon(
            onPressed: _createMember,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('添加成员'),
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        if (_error != null) ...[
          _RefreshNotice(error: _error!),
          const SizedBox(height: LumaSpacing.sm),
        ],
        if (users.isEmpty)
          const EmptyState(
            icon: Icons.group_outlined,
            title: '暂无成员',
            message: '添加家庭成员后，可分别控制其媒体源和设备令牌。',
          )
        else
          ...users.map(_userTile),
      ],
    );
  }

  Widget _userTile(AccessUser user) {
    final colorScheme = Theme.of(context).colorScheme;
    final online = user.enabled && user.online;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            user.isAdmin
                ? Icons.admin_panel_settings_outlined
                : Icons.person_outline_rounded,
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.circle,
                  size: 10,
                  color: online
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(user.name),
      subtitle: Text(
        '${user.isAdmin
            ? '管理员'
            : user.enabled
            ? '成员 · 已启用'
            : '成员 · 已停用'} · ${online ? '在线' : '离线'}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _openMember(user),
    );
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() => _error = null);
    try {
      final users = await widget.access.listUsers();
      if (!mounted || generation != _loadGeneration) return;
      users.sort((left, right) {
        if (left.isAdmin != right.isAdmin) return left.isAdmin ? -1 : 1;
        return left.name.compareTo(right.name);
      });
      setState(() => _users = users);
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    }
  }

  Future<void> _createMember() async {
    await context.pushNamed<bool>(AppRoute.newMember);
    if (mounted) _load();
  }

  Future<void> _openMember(AccessUser user) async {
    await context.pushNamed<void>(
      AppRoute.memberDetail,
      pathParameters: {'userId': user.id},
      extra: user,
    );
    if (mounted) _load();
  }
}

class _RefreshNotice extends StatelessWidget {
  const _RefreshNotice({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(LumaRadii.medium),
    ),
    child: Padding(
      padding: const EdgeInsets.all(LumaSpacing.sm),
      child: Text('刷新失败，正在显示上次结果：$error'),
    ),
  );
}
