import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/extensions.dart';
import '../../../core/theme.dart';
import '../../../data/models/api_access.dart';
import '../../../data/models/api_source.dart';
import '../../../data/repositories/access_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../shared/layout/constrained_page_list.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/library/library_kind_presentation.dart';
import '../../../shared/layout/surface_card.dart';
import '../../../shared/states/empty_state.dart';
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
  List<AccessToken>? _tokens;
  Set<String> _grants = {};
  Object? _loadError;
  bool _savingUser = false;
  final _savingSources = <String>{};
  final _revokingTokens = <String>{};
  int _loadGeneration = 0;

  bool get _isBusy =>
      _savingUser || _savingSources.isNotEmpty || _revokingTokens.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_user.name),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _isBusy ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _body(),
  );

  Widget _body() {
    final sources = _sources;
    final tokens = _tokens;
    if (sources == null || tokens == null) {
      if (_loadError != null) {
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
    final sourceIds = sources.map((source) => source.id).toSet();
    final missingGrantIds = _grants.difference(sourceIds).toList()..sort();
    return ConstrainedPageList(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      children: [
        if (_loadError != null) ...[
          _InlineError(error: _loadError!),
          const SizedBox(height: LumaSpacing.md),
        ],
        _profileCard(),
        const SizedBox(height: LumaSpacing.xl),
        if (_user.isAdmin) ...[
          const SectionHeader(title: '媒体源访问'),
          const SizedBox(height: LumaSpacing.xs),
          Text(
            '管理员始终可以访问全部媒体源，不能单独调整授权。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ] else ...[
          const SectionHeader(title: '媒体源访问'),
          const SizedBox(height: LumaSpacing.xs),
          if (sources.isEmpty)
            Text(
              '当前没有可授权的媒体源。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...sources.map(_sourceGrantTile),
          if (missingGrantIds.isNotEmpty) ...[
            const SizedBox(height: LumaSpacing.md),
            const Text('已删除的媒体源'),
            ...missingGrantIds.map(_missingGrantTile),
          ],
        ],
        const SizedBox(height: LumaSpacing.xl),
        const SectionHeader(title: '设备令牌'),
        const SizedBox(height: LumaSpacing.xs),
        FilledButton.icon(
          onPressed: _isBusy ? null : _issueToken,
          icon: const Icon(Icons.add_rounded),
          label: const Text('签发新令牌'),
        ),
        const SizedBox(height: LumaSpacing.sm),
        if (tokens.isEmpty)
          Text(
            '尚未签发设备令牌。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...tokens.map(
            (token) => AccessTokenTile(
              token: token,
              revoking: _revokingTokens.contains(token.id),
              onRevoke: _isBusy ? null : () => _revokeToken(token),
            ),
          ),
      ],
    );
  }

  Widget _profileCard() => SurfaceCard(
    child: Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _user.isAdmin
                ? Icons.admin_panel_settings_outlined
                : Icons.person_outline_rounded,
          ),
          title: Text(_user.name),
          subtitle: Text(
            _user.isAdmin
                ? '管理员'
                : _user.enabled
                ? '成员 · 已启用'
                : '成员 · 已停用',
          ),
          trailing: IconButton(
            tooltip: '修改名称',
            onPressed: _savingUser ? null : _editName,
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
        if (!_user.isAdmin) ...[
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('允许成员登录'),
            subtitle: Text(
              _user.enabled ? '停用后该成员的全部令牌立即失效' : '启用后未过期令牌可以继续使用',
            ),
            value: _user.enabled,
            onChanged: _savingUser ? null : _changeEnabled,
          ),
        ],
      ],
    ),
  );

  Widget _sourceGrantTile(Source source) {
    final granted = _grants.contains(source.id);
    final saving = _savingSources.contains(source.id);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: granted,
      onChanged: saving || _isBusy
          ? null
          : (next) => _changeGrant(source.id, next == true),
      title: Text(source.name),
      subtitle: Text(_sourceLabel(source)),
      secondary: saving
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
    );
  }

  Widget _missingGrantTile(String sourceId) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.folder_off_outlined),
    title: const Text('已删除的媒体源'),
    subtitle: Text(sourceId),
    trailing: _savingSources.contains(sourceId)
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : IconButton(
            tooltip: '移除残留授权',
            onPressed: _isBusy ? null : () => _changeGrant(sourceId, false),
            icon: const Icon(Icons.remove_circle_outline),
          ),
  );

  Future<void> _load() async {
    if (_isBusy) return;
    final generation = ++_loadGeneration;
    setState(() => _loadError = null);
    try {
      final values = await Future.wait<Object>([
        widget.sources.list(refresh: true),
        widget.access.listTokens(_user.id),
        _user.isAdmin
            ? Future<Object>.value(<String>[])
            : widget.access.listGrants(_user.id),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _sources = values[0] as List<Source>;
        _tokens = values[1] as List<AccessToken>;
        _grants = Set<String>.from(values[2] as List<String>);
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _user.name);
    final name = await showDialog<String>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (context) => AlertDialog(
        title: const Text('修改名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null || name.trim() == _user.name) return;
    if (name.trim().isEmpty) {
      context.showLumaSnack('请输入成员名称');
      return;
    }
    await _updateUser(name: name.trim());
  }

  Future<void> _changeEnabled(bool enabled) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: enabled ? '启用成员？' : '停用成员？',
      message: enabled ? '该成员的未过期令牌将恢复可用。' : '该成员的全部令牌会立即失效。',
      confirmLabel: enabled ? '启用' : '停用',
    );
    if (!confirmed || !mounted) return;
    await _updateUser(enabled: enabled);
  }

  Future<void> _updateUser({String? name, bool? enabled}) async {
    if (_savingUser) return;
    _loadGeneration++;
    setState(() => _savingUser = true);
    try {
      final updated = await widget.access.updateUser(
        _user.id,
        name: name,
        enabled: enabled,
      );
      if (!mounted) return;
      setState(() => _user = updated);
      context.showLumaSnack('成员资料已更新');
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('更新失败：$error');
    } finally {
      if (mounted) setState(() => _savingUser = false);
    }
  }

  Future<void> _changeGrant(String sourceId, bool grant) async {
    if (_savingSources.contains(sourceId) || _isBusy) return;
    _loadGeneration++;
    setState(() => _savingSources.add(sourceId));
    try {
      if (grant) {
        await widget.access.grantSource(_user.id, sourceId);
      } else {
        await widget.access.revokeSource(_user.id, sourceId);
      }
      if (!mounted) return;
      setState(() {
        if (grant) {
          _grants.add(sourceId);
        } else {
          _grants.remove(sourceId);
        }
      });
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('授权更新失败：$error');
    } finally {
      if (mounted) setState(() => _savingSources.remove(sourceId));
    }
  }

  Future<void> _issueToken() async {
    await context.pushNamed<IssuedAccessToken>(
      AppRoute.issueToken,
      pathParameters: {'userId': _user.id},
      extra: _user,
    );
    if (mounted) await _load();
  }

  Future<void> _revokeToken(AccessToken token) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: '吊销令牌？',
      message: '吊销后 ${token.name} 将立即无法访问服务器。',
      confirmLabel: '吊销',
    );
    if (!confirmed || !mounted || _isBusy) return;
    _loadGeneration++;
    setState(() => _revokingTokens.add(token.id));
    try {
      await widget.access.revokeToken(token.id);
      if (!mounted) return;
      context.showLumaSnack('令牌已吊销');
      await _loadTokensAfterMutation();
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('吊销失败：$error');
    } finally {
      if (mounted) setState(() => _revokingTokens.remove(token.id));
    }
  }

  Future<void> _loadTokensAfterMutation() async {
    final generation = ++_loadGeneration;
    final tokens = await widget.access.listTokens(_user.id);
    if (!mounted || generation != _loadGeneration) return;
    setState(() => _tokens = tokens);
  }

  static String _sourceLabel(Source source) =>
      '${LibraryKindPresentation.label(source.libraryKind)} · ${source.status}';
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(LumaRadii.medium),
    ),
    child: Padding(
      padding: const EdgeInsets.all(LumaSpacing.md),
      child: Text('刷新失败：$error'),
    ),
  );
}
