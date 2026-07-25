// 登录设备组件只展示可撤销会话，不暴露任何会话密钥。
import 'package:flutter/material.dart';

import '../../../data/models/api_access.dart';

class LoginSessionTile extends StatelessWidget {
  const LoginSessionTile({
    super.key,
    required this.session,
    required this.revoking,
    required this.onRevoke,
  });

  final LoginSession session;
  final bool revoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final expiresAt = session.expiresAt;
    final status = session.isRevoked
        ? '已撤销'
        : expiresAt == null
        ? '长期有效'
        : !expiresAt.isAfter(DateTime.now())
        ? '已过期'
        : '至 ${formatAccessDate(context, expiresAt)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.devices_outlined),
      title: Text(session.name),
      subtitle: Text(status),
      trailing: session.isRevoked
          ? const Text('已撤销')
          : revoking
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: '撤销设备',
              onPressed: onRevoke,
              icon: const Icon(Icons.block_outlined),
            ),
    );
  }
}

String formatAccessDate(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatMediumDate(value.toLocal());
