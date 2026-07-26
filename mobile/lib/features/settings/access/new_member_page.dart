// 新成员页面负责创建账号和来源授权，密码只在提交时传给访问仓储。
import 'package:flutter/material.dart';

import '../../../core/extensions.dart';
import '../../../core/theme.dart';
import '../../../data/models/api_access.dart';
import '../../../data/models/api_source.dart';
import '../../../data/repositories/access_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../shared/layout/constrained_page_list.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/states/empty_state.dart';
import '../../../shared/states/skeleton.dart';
import 'access_request_id.dart';

class NewMemberPage extends StatefulWidget {
  const NewMemberPage({super.key, required this.access, required this.sources});
  final AccessRepository access;
  final SourceRepository sources;
  @override
  State<NewMemberPage> createState() => _NewMemberPageState();
}

class _NewMemberPageState extends State<NewMemberPage> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _selected = <String>{};
  final String _requestId = newAccessRequestId();
  List<Source>? _sources;
  AccessUser? _createdUser;
  Set<String>? _pendingSourceIds;
  Object? _error;
  bool _submitting = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('添加成员')),
    body: _body(),
  );
  Widget _body() {
    final sources = _sources;
    final accountCreated = _createdUser != null;
    if (sources == null) {
      if (_error != null) {
        return EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '无法读取媒体源',
          message: '请检查服务器连接后重试。',
          action: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载'),
          ),
        );
      }
      return const SettingsListSkeleton(items: 4, showAction: true);
    }
    return ConstrainedPageList(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      children: [
        TextField(
          controller: _name,
          enabled: !_submitting && !accountCreated,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: '成员名称',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        TextField(
          controller: _username,
          enabled: !_submitting && !accountCreated,
          maxLength: 32,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '用户名',
            hintText: 'alice',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        TextField(
          controller: _password,
          enabled: !_submitting && !accountCreated,
          maxLength: 128,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '初始密码',
            helperText: '10 至 128 个字符',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        TextField(
          controller: _confirmation,
          enabled: !_submitting && !accountCreated,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '确认密码',
            prefixIcon: Icon(Icons.lock_reset_outlined),
          ),
        ),
        const SizedBox(height: LumaSpacing.lg),
        const SectionHeader(title: '可访问的媒体源'),
        ...sources.map(
          (source) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _selected.contains(source.id),
            onChanged: _submitting || accountCreated
                ? null
                : (value) => setState(
                    () => value == true
                        ? _selected.add(source.id)
                        : _selected.remove(source.id),
                  ),
            title: Text(source.name),
          ),
        ),
        const SizedBox(height: LumaSpacing.lg),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_alt_1_outlined),
          label: Text(
            _submitting
                ? accountCreated
                      ? '正在重试授权'
                      : '正在创建'
                : accountCreated
                ? '继续授权'
                : '创建成员',
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final value = await widget.sources.list(refresh: true);
      if (mounted) setState(() => _sources = value);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  /// 创建账号后逐个授权；部分失败时保留成员、request ID 和待授权集合供重试。
  Future<void> _submit() async {
    if (_submitting) return;
    if (_createdUser == null &&
        (_name.text.trim().isEmpty ||
            _username.text.trim().isEmpty ||
            _password.text.isEmpty)) {
      context.showLumaSnack('请完整填写账号信息');
      return;
    }
    if (_createdUser == null && _password.text != _confirmation.text) {
      context.showLumaSnack('两次输入的密码不一致');
      return;
    }
    final passwordLength = _password.text.runes.length;
    if (_createdUser == null && (passwordLength < 10 || passwordLength > 128)) {
      context.showLumaSnack('密码须为 10 至 128 个字符');
      return;
    }
    setState(() => _submitting = true);
    try {
      var user = _createdUser;
      if (user == null) {
        user = await widget.access.createUser(
          _name.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          requestId: _requestId,
        );
        if (!mounted) return;
        _createdUser = user;
        _pendingSourceIds = Set.of(_selected);
        _password.clear();
        _confirmation.clear();
      }
      final pending = _pendingSourceIds!;
      for (final sourceID in pending.toList(growable: false)) {
        try {
          await widget.access.grantSource(user.id, sourceID);
          pending.remove(sourceID);
        } on Object {
          // 继续尝试其余来源，确保一次提交可完成尽可能多的授权。
        }
      }
      if (!mounted) return;
      if (pending.isNotEmpty) {
        context.showLumaSnack(
          '成员已创建，但仍有 ${pending.length} 个媒体源未授权；请点击“继续授权”重试。',
        );
        return;
      }
      context.showLumaSnack('成员已创建');
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('成员创建失败：$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
