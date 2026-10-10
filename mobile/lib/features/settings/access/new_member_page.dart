// 新成员页面负责创建账号和来源授权，密码只在提交时传给访问仓储。
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
  bool _submitted = false;
  bool _passwordVisible = false;
  bool _confirmationVisible = false;
  @override
  void initState() {
    super.initState();
    for (final field in [_name, _username, _password, _confirmation]) {
      field.addListener(_revalidate);
    }
    _load();
  }

  /// 提交失败后随输入刷新字段错误，修正后提示立即消失。
  void _revalidate() {
    if (_submitted && mounted) setState(() {});
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
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          decoration: InputDecoration(
            labelText: '成员名称',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            errorText: _submitted && _name.text.trim().isEmpty
                ? '请填写成员名称'
                : null,
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        TextField(
          controller: _username,
          enabled: !_submitting && !accountCreated,
          maxLength: 32,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration: InputDecoration(
            labelText: '用户名',
            hintText: 'alice',
            prefixIcon: const Icon(Icons.badge_outlined),
            errorText: _submitted && _username.text.trim().isEmpty
                ? '请填写用户名'
                : null,
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        TextField(
          controller: _password,
          enabled: !_submitting && !accountCreated,
          maxLength: 128,
          obscureText: !_passwordVisible,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: '初始密码',
            helperText: '10 至 128 个字符',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            errorText: _submitted ? _passwordError() : null,
            suffixIcon: IconButton(
              tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
            ),
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        TextField(
          controller: _confirmation,
          enabled: !_submitting && !accountCreated,
          obscureText: !_confirmationVisible,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: '确认密码',
            prefixIcon: const Icon(Icons.lock_reset_outlined),
            errorText:
                _submitted && _password.text != _confirmation.text
                ? '两次输入的密码不一致'
                : null,
            suffixIcon: IconButton(
              tooltip: _confirmationVisible ? '隐藏密码' : '显示密码',
              icon: Icon(
                _confirmationVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () => setState(
                () => _confirmationVisible = !_confirmationVisible,
              ),
            ),
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
        AdaptiveActionWidth(
          child: FilledButton.icon(
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

  /// 密码字段的错误文案；空值与长度规则沿用提交时的校验。
  String? _passwordError() {
    if (_password.text.isEmpty) return '请填写初始密码';
    final length = _password.text.runes.length;
    if (length < 10 || length > 128) return '密码须为 10 至 128 个字符';
    return null;
  }

  bool _hasValidationError() =>
      _name.text.trim().isEmpty ||
      _username.text.trim().isEmpty ||
      _passwordError() != null ||
      _password.text != _confirmation.text;

  /// 创建账号后逐个授权；部分失败时保留成员、request ID 和待授权集合供重试。
  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitted = true);
    if (_createdUser == null && _hasValidationError()) return;
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
