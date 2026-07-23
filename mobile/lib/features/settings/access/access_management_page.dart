import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_access.dart';
import '../../../data/repositories/access_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../shared/layout/constrained_page_list.dart';
import '../../../shared/states/empty_state.dart';
import 'member_detail_page.dart';
import 'new_member_page.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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
      return const Center(child: CircularProgressIndicator());
    }
    return ConstrainedPageList(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      children: [
        Text(
          '管理家庭成员可访问的媒体源和设备令牌。令牌明文只在签发时显示一次。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: LumaSpacing.lg),
        FilledButton.icon(
          onPressed: _createMember,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('添加成员'),
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

  Widget _userTile(AccessUser user) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      user.isAdmin
          ? Icons.admin_panel_settings_outlined
          : Icons.person_outline_rounded,
    ),
    title: Text(user.name),
    subtitle: Text(
      user.isAdmin
          ? '管理员'
          : user.enabled
          ? '成员 · 已启用'
          : '成员 · 已停用',
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => _openMember(user),
  );

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
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            NewMemberPage(access: widget.access, sources: widget.sources),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openMember(AccessUser user) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MemberDetailPage(
          access: widget.access,
          sources: widget.sources,
          user: user,
        ),
      ),
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
