import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_access.dart';
import '../../../shared/layout/surface_card.dart';

class AccessExpiryField extends StatelessWidget {
  const AccessExpiryField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final expiresAt = value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: const Icon(Icons.event_outlined),
      title: const Text('有效期'),
      subtitle: Text(
        expiresAt == null ? '永不过期' : formatAccessDate(context, expiresAt),
      ),
      onTap: enabled ? () => _pickDate(context) : null,
      trailing: expiresAt == null
          ? const Icon(Icons.chevron_right_rounded)
          : IconButton(
              tooltip: '清除有效期',
              onPressed: enabled ? () => onChanged(null) : null,
              icon: const Icon(Icons.close_rounded),
            ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = value?.toLocal() ?? now.add(const Duration(days: 30));
    final selected = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (selected == null || !context.mounted) return;
    // A date-only control expires at the end of the selected local day.
    onChanged(
      DateTime(selected.year, selected.month, selected.day, 23, 59, 59),
    );
  }
}

class OneTimeTokenPanel extends StatelessWidget {
  const OneTimeTokenPanel({
    super.key,
    required this.token,
    required this.onComplete,
  });

  final String token;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.key_rounded, size: 48),
        const SizedBox(height: LumaSpacing.md),
        Text(
          '请立即保存访问令牌',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: LumaSpacing.xs),
        Text(
          '离开此页面后无法再次查看明文令牌。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: LumaSpacing.lg),
        SurfaceCard(
          child: SelectableText(
            token,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: token));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('访问令牌已复制')));
            }
          },
          icon: const Icon(Icons.content_copy_outlined),
          label: const Text('复制令牌'),
        ),
        const SizedBox(height: LumaSpacing.sm),
        FilledButton(onPressed: onComplete, child: const Text('我已安全保存')),
      ],
    );
  }
}

class AccessTokenTile extends StatelessWidget {
  const AccessTokenTile({
    super.key,
    required this.token,
    required this.revoking,
    required this.onRevoke,
  });

  final AccessToken token;
  final bool revoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final status = token.isRevoked
        ? '已吊销'
        : token.isExpired
        ? '已过期'
        : token.expiresAt == null
        ? '长期有效'
        : '至 ${formatAccessDate(context, token.expiresAt!)}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.key_outlined),
      title: Text(token.name),
      subtitle: Text('${token.tokenPrefix} · $status'),
      trailing: token.isRevoked
          ? const Text('已吊销')
          : revoking
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: '吊销令牌',
              onPressed: onRevoke,
              icon: const Icon(Icons.block_outlined),
            ),
    );
  }
}

String formatAccessDate(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatMediumDate(value.toLocal());
