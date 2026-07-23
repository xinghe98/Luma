import 'package:flutter/material.dart';

import '../../../core/extensions.dart';
import '../../../core/theme.dart';
import '../../../data/models/api_access.dart';
import '../../../data/repositories/access_repository.dart';
import '../../../shared/layout/constrained_page_list.dart';
import 'access_request_id.dart';
import 'access_widgets.dart';

class IssueTokenPage extends StatefulWidget {
  const IssueTokenPage({super.key, required this.access, required this.user});

  final AccessRepository access;
  final AccessUser user;

  @override
  State<IssueTokenPage> createState() => _IssueTokenPageState();
}

class _IssueTokenPageState extends State<IssueTokenPage> {
  final _name = TextEditingController();
  DateTime? _expiresAt;
  IssuedAccessToken? _issued;
  bool _issuing = false;
  bool _tokenDelivered = false;
  bool _revoking = false;
  String? _requestId;

  @override
  void dispose() {
    _name.dispose();
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
        appBar: AppBar(title: Text(issued == null ? '签发访问令牌' : '保存访问令牌')),
        body: ConstrainedPageList(
          padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
          children: issued == null ? _form() : [_secret(issued)],
        ),
      ),
    );
  }

  List<Widget> _form() => [
    Text(
      '为 ${widget.user.name} 签发设备专用令牌。令牌明文只会显示一次。',
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    const SizedBox(height: LumaSpacing.lg),
    TextField(
      controller: _name,
      enabled: !_issuing,
      maxLength: 80,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _issue(),
      decoration: const InputDecoration(
        labelText: '设备名称',
        hintText: '例如：Alice 的手机',
        prefixIcon: Icon(Icons.phone_android_outlined),
      ),
    ),
    const SizedBox(height: LumaSpacing.sm),
    AccessExpiryField(
      value: _expiresAt,
      enabled: !_issuing,
      onChanged: (value) => setState(() => _expiresAt = value),
    ),
    const SizedBox(height: LumaSpacing.lg),
    FilledButton.icon(
      onPressed: _issuing ? null : _issue,
      icon: _issuing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.key_rounded),
      label: Text(_issuing ? '正在签发' : '签发令牌'),
    ),
  ];

  Widget _secret(IssuedAccessToken issued) => OneTimeTokenPanel(
    token: issued.token,
    onComplete: () {
      setState(() => _tokenDelivered = true);
      Navigator.of(context).pop(issued);
    },
  );

  Future<void> _discardToken(IssuedAccessToken issued) async {
    setState(() => _revoking = true);
    try {
      await widget.access.revokeToken(issued.id);
      if (!mounted) return;
      setState(() => _tokenDelivered = true);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('无法吊销未保存的令牌：$error');
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  Future<void> _issue() async {
    if (_issuing) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      context.showLumaSnack('请输入设备名称');
      return;
    }
    setState(() => _issuing = true);
    try {
      final issued = await widget.access.issueToken(
        widget.user.id,
        name: name,
        expiresAt: _expiresAt,
        requestId: _requestId ??= newAccessRequestId(),
      );
      if (!mounted) return;
      setState(() => _issued = issued);
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('签发失败：$error');
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }
}
