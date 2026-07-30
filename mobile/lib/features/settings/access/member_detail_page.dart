// 成员详情页面管理账号状态、来源授权、密码重置和登录设备。
import 'package:flutter/material.dart';

import '../../../core/extensions.dart';
import '../../../core/theme.dart';
import '../../../data/models/api_access.dart';
import '../../../data/models/api_source.dart';
import '../../../data/repositories/access_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../shared/layout/adaptive_action_width.dart';
import '../../../shared/layout/constrained_page_list.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/states/empty_state.dart';
import '../../../shared/states/error_state.dart';
import '../../../shared/states/skeleton.dart';
import '../dialogs/confirmation_dialog.dart';
import 'access_widgets.dart';

class MemberDetailPage extends StatefulWidget {
  const MemberDetailPage({
    super.key,
    required this.access,
    required this.sources,
    required this.user,
  });
  final AccessRepository access;
  final SourceRepository sources;
  final AccessUser user;
  @override
  State<MemberDetailPage> createState() => _MemberDetailPageState();
}

class _MemberDetailPageState extends State<MemberDetailPage> {
  late AccessUser _user;
  List<Source>? _sources;
  List<LoginSession>? _sessions;
  Set<String> _grants = {};
  Object? _error;
  final _saving = <String>{};
  bool _savingUser = false;
  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _load();
  }

  bool get _busy => _savingUser || _saving.isNotEmpty;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_user.name),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _body(),
  );
  Widget _body() {
    if (_sources == null || _sessions == null) {
      if (_error != null) {
        return EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '无法读取成员资料',
          message: '请检查服务器连接后重试。',
          action: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载'),
          ),
        );
      }
      return const SettingsListSkeleton(items: 4);
    }
    return ConstrainedPageList(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      children: [
        if (_error != null)
          ErrorState(
            compact: true,
            title: '成员资料刷新失败',
            message: '当前仍显示上次成功加载的资料。',
            retryLabel: '重试刷新',
            onRetry: _load,
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _user.isAdmin
                ? Icons.admin_panel_settings_outlined
                : Icons.person_outline_rounded,
          ),
          title: Text(_user.name),
          subtitle: Text(
            '@${_user.username} · ${_user.enabled ? '已启用' : '已停用'}',
          ),
        ),
        if (!_user.isAdmin)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('允许成员登录'),
            value: _user.enabled,
            onChanged: _busy ? null : _setEnabled,
          ),
        const SizedBox(height: LumaSpacing.md),
        AdaptiveActionWidth(
          maxWidth: 240,
          child: FilledButton.tonalIcon(
            onPressed: _busy ? null : _resetPassword,
            icon: const Icon(Icons.lock_reset_outlined),
            label: const Text('重置密码'),
          ),
        ),
        const SizedBox(height: LumaSpacing.xl),
        const SectionHeader(title: '媒体源访问'),
        if (_user.isAdmin)
          const Text('管理员始终可以访问全部媒体源。')
        else
          ..._sources!.map(
            (source) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _grants.contains(source.id),
              onChanged: _busy
                  ? null
                  : (value) => _changeGrant(source.id, value == true),
              title: Text(source.name),
            ),
          ),
        const SizedBox(height: LumaSpacing.xl),
        const SectionHeader(title: '登录设备'),
        if (_sessions!.isEmpty)
          const Text('尚无登录设备。')
        else
          ..._sessions!.map(
            (session) => LoginSessionTile(
              session: session,
              revoking: _saving.contains(session.id),
              onRevoke: _busy ? null : () => _revokeSession(session),
            ),
          ),
      ],
    );
  }

  /// 拉取成员资料。force 用于撤销等 mutation 之后，忽略本地 busy 锁。
  Future<void> _load({bool force = false}) async {
    if (_busy && !force) return;
    setState(() => _error = null);
    try {
      final values = await Future.wait<Object>([
        _sourcesFuture(),
        widget.access.listSessions(_user.id),
        _user.isAdmin
            ? Future.value(<String>[])
            : widget.access.listGrants(_user.id),
      ]);
      if (mounted) {
        setState(() {
          _sources = values[0] as List<Source>;
          _sessions = (values[1] as List<LoginSession>)
              .where((session) => !session.isRevoked)
              .toList(growable: false);
          _grants = Set<String>.from(values[2] as List<String>);
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<List<Source>> _sourcesFuture() => widget.sources.list(refresh: true);
  Future<void> _setEnabled(bool value) async {
    setState(() => _savingUser = true);
    try {
      final user = await widget.access.updateUser(_user.id, enabled: value);
      if (mounted) setState(() => _user = user);
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('更新失败：$error');
    } finally {
      if (mounted) setState(() => _savingUser = false);
    }
  }

  Future<void> _changeGrant(String sourceID, bool grant) async {
    setState(() => _saving.add(sourceID));
    try {
      if (grant) {
        await widget.access.grantSource(_user.id, sourceID);
      } else {
        await widget.access.revokeSource(_user.id, sourceID);
      }
      if (mounted) {
        setState(
          () => grant ? _grants.add(sourceID) : _grants.remove(sourceID),
        );
      }
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('授权更新失败：$error');
    } finally {
      if (mounted) setState(() => _saving.remove(sourceID));
    }
  }

  Future<void> _revokeSession(LoginSession session) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: '撤销设备？',
      message: '该设备需要重新输入用户名和密码登录。',
      confirmLabel: '撤销',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving.add(session.id));
    try {
      await widget.access.revokeSession(session.id);
      if (!mounted) return;
      // 先本地移除，避免 _load 被 busy 挡住导致列表不刷新。
      setState(() {
        _sessions = [
          for (final item in _sessions ?? const <LoginSession>[])
            if (item.id != session.id) item,
        ];
        _saving.remove(session.id);
      });
      await _load(force: true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving.remove(session.id));
        context.showLumaSnack('撤销失败：$error');
      }
    }
  }

  Future<void> _resetPassword() async {
    final next = await showDialog<String>(
      context: context,
      // 取消或点遮罩后立即移除遮罩，避免退场动画与 controller 生命周期冲突。
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => const _ResetPasswordDialog(),
    );
    if (!mounted || next == null) return;
    setState(() => _savingUser = true);
    try {
      await widget.access.resetPassword(_user.id, next);
      if (!mounted) return;
      setState(() {
        _sessions = const [];
        _savingUser = false;
      });
      context.showLumaSnack('密码已重置，成员设备已退出登录');
      await _load(force: true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _savingUser = false);
        context.showLumaSnack('重置失败：$error');
      }
    }
  }
}

/// 重置密码弹窗；自行持有输入控制器，在 State.dispose 中释放。
class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog();

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController _password;
  late final TextEditingController _confirmation;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController();
    _confirmation = TextEditingController();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  /// 校验两次密码一致且长度足够后关闭弹窗并返回新密码。
  void _confirm() {
    final password = _password.text;
    final confirmation = _confirmation.text;
    if (password != confirmation) {
      context.showLumaSnack('两次输入的密码不一致');
      return;
    }
    final passwordLength = password.runes.length;
    if (passwordLength < 10 || passwordLength > 128) {
      context.showLumaSnack('密码须为 10 至 128 个字符');
      return;
    }
    Navigator.pop(context, password);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('重置密码'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _password,
          maxLength: 128,
          obscureText: true,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '新密码',
            helperText: '10 至 128 个字符',
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        TextField(
          controller: _confirmation,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: '确认密码'),
          onSubmitted: (_) => _confirm(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _confirm, child: const Text('确认')),
    ],
  );
}
