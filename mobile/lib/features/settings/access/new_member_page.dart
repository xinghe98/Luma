import 'package:flutter/material.dart';

import '../../../core/extensions.dart';
import '../../../core/theme.dart';
import '../../../data/models/api_access.dart';
import '../../../data/models/api_source.dart';
import '../../../data/repositories/access_repository.dart';
import '../../../data/repositories/source_repository.dart';
import '../../../shared/layout/constrained_page_list.dart';
import '../../../shared/layout/section_header.dart';
import '../../../shared/library/library_kind_presentation.dart';
import '../../../shared/states/empty_state.dart';
import '../../../shared/states/skeleton.dart';
import 'access_request_id.dart';
import 'access_widgets.dart';

class NewMemberPage extends StatefulWidget {
  const NewMemberPage({super.key, required this.access, required this.sources});

  final AccessRepository access;
  final SourceRepository sources;

  @override
  State<NewMemberPage> createState() => _NewMemberPageState();
}

class _NewMemberPageState extends State<NewMemberPage> {
  final _memberName = TextEditingController();
  final _tokenName = TextEditingController();
  final _selectedSourceIds = <String>{};
  final _pendingGrantIds = <String>{};
  List<Source>? _sources;
  AccessUser? _created;
  IssuedAccessToken? _issued;
  DateTime? _expiresAt;
  Object? _loadError;
  Object? _workflowError;
  bool _submitting = false;
  bool _tokenDelivered = false;
  bool _revoking = false;
  String? _createRequestId;
  String? _issueRequestId;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    _memberName.dispose();
    _tokenName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final issued = _issued;
    return PopScope(
      canPop: issued == null || _tokenDelivered,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && issued != null && !_revoking) _discardToken(issued);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(issued == null ? '添加成员' : '保存访问令牌')),
        body: issued != null
            ? ConstrainedPageList(
                padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
                children: [
                  OneTimeTokenPanel(
                    token: issued.token,
                    onComplete: () {
                      setState(() => _tokenDelivered = true);
                      Navigator.of(context).pop(true);
                    },
                  ),
                ],
              )
            : _body(),
      ),
    );
  }

  Widget _body() {
    final sources = _sources;
    if (sources == null) {
      if (_loadError != null) {
        return EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '无法读取媒体源',
          message: '请检查服务器连接后重试。',
          action: FilledButton.icon(
            onPressed: _loadSources,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新加载'),
          ),
        );
      }
      return const SettingsListSkeleton(items: 3, showAction: true);
    }
    final created = _created;
    final isCreated = created != null;
    return ConstrainedPageList(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      children: [
        if (_workflowError != null) ...[
          _WorkflowNotice(
            created: created,
            pendingGrants: _pendingGrantIds.length,
            error: _workflowError!,
          ),
          const SizedBox(height: LumaSpacing.lg),
        ],
        Text(
          isCreated ? '成员已创建。完成剩余授权并签发令牌后即可交付。' : '创建成员、授予媒体源访问权并签发设备令牌。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: LumaSpacing.lg),
        TextField(
          controller: _memberName,
          enabled: !_submitting && !isCreated,
          maxLength: 80,
          autofocus: !isCreated,
          decoration: const InputDecoration(
            labelText: '成员名称',
            hintText: '例如：Alice',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        const SectionHeader(title: '可访问的媒体源'),
        const SizedBox(height: LumaSpacing.xs),
        if (sources.isEmpty)
          Text(
            '当前没有可授权的媒体源，成员创建后将暂时看不到媒体。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...sources.map(
            (source) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selectedSourceIds.contains(source.id),
              onChanged: _submitting || isCreated
                  ? null
                  : (selected) => setState(() {
                      if (selected == true) {
                        _selectedSourceIds.add(source.id);
                      } else {
                        _selectedSourceIds.remove(source.id);
                      }
                    }),
              title: Text(source.name),
              subtitle: Text(_sourceLabel(source)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
        const SizedBox(height: LumaSpacing.md),
        TextField(
          controller: _tokenName,
          enabled: !_submitting,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: '首个设备名称',
            hintText: '例如：Alice 的手机',
            prefixIcon: Icon(Icons.phone_android_outlined),
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        AccessExpiryField(
          value: _expiresAt,
          enabled: !_submitting,
          onChanged: (value) => setState(() => _expiresAt = value),
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
          label: Text(_submitLabel()),
        ),
      ],
    );
  }

  String _submitLabel() {
    if (_submitting) return '正在处理';
    if (_created == null) return '创建成员并签发令牌';
    if (_pendingGrantIds.isNotEmpty) return '继续完成授权';
    return '重试签发令牌';
  }

  Future<void> _loadSources() async {
    final generation = ++_loadGeneration;
    setState(() => _loadError = null);
    try {
      final sources = await widget.sources.list(refresh: true);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _sources = sources);
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadError = error);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final memberName = _memberName.text.trim();
    final tokenName = _tokenName.text.trim();
    if (_created == null && memberName.isEmpty) {
      context.showLumaSnack('请输入成员名称');
      return;
    }
    if (tokenName.isEmpty) {
      context.showLumaSnack('请输入设备名称');
      return;
    }
    setState(() {
      _submitting = true;
      _workflowError = null;
    });
    try {
      var member = _created;
      if (member == null) {
        member = await widget.access.createUser(
          memberName,
          requestId: _createRequestId ??= newAccessRequestId(),
        );
        if (!mounted) return;
        setState(() {
          _created = member;
          _pendingGrantIds
            ..clear()
            ..addAll(_selectedSourceIds);
        });
      }

      // The backend has no batch transaction. Keep the created member and the
      // remaining grants so retrying cannot create another member or token.
      for (final sourceId in List<String>.from(_pendingGrantIds)) {
        await widget.access.grantSource(member.id, sourceId);
        if (!mounted) return;
        setState(() => _pendingGrantIds.remove(sourceId));
      }

      final issued = await widget.access.issueToken(
        member.id,
        name: tokenName,
        expiresAt: _expiresAt,
        requestId: _issueRequestId ??= newAccessRequestId(),
      );
      if (!mounted) return;
      setState(() => _issued = issued);
    } on Object catch (error) {
      if (mounted) setState(() => _workflowError = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _discardToken(IssuedAccessToken issued) async {
    setState(() => _revoking = true);
    try {
      await widget.access.revokeToken(issued.id);
      if (!mounted) return;
      setState(() => _tokenDelivered = true);
      Navigator.of(context).pop(false);
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('无法吊销未保存的令牌：$error');
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  static String _sourceLabel(Source source) =>
      '${LibraryKindPresentation.label(source.libraryKind)} · ${source.status}';
}

class _WorkflowNotice extends StatelessWidget {
  const _WorkflowNotice({
    required this.created,
    required this.pendingGrants,
    required this.error,
  });

  final AccessUser? created;
  final int pendingGrants;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(LumaRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LumaSpacing.md),
        child: Text(
          created == null
              ? '创建失败：$error'
              : '成员 ${created!.name} 已创建，仍有 $pendingGrants 项授权或令牌签发未完成：$error',
        ),
      ),
    );
  }
}
