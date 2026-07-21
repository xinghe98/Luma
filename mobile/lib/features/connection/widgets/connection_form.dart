import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../connection_controller.dart';
import 'connection_notice.dart';

class ConnectionForm extends StatelessWidget {
  const ConnectionForm({
    super.key,
    required this.controller,
    required this.hostController,
    required this.portController,
    required this.tokenController,
    required this.scheme,
    required this.enabled,
    required this.onSchemeChanged,
    required this.onConnect,
  });

  final ConnectionController controller;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController tokenController;
  final String scheme;
  final bool enabled;
  final ValueChanged<String> onSchemeChanged;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: hostController,
                enabled: enabled && !controller.isLoading,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'IP 地址',
                  hintText: '192.168.1.10',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
            ),
            const SizedBox(width: LumaSpacing.sm),
            Expanded(
              flex: 2,
              child: TextField(
                controller: portController,
                enabled: enabled && !controller.isLoading,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '8080',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: LumaSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: scheme,
          onChanged: !enabled || controller.isLoading
              ? null
              : (value) {
                  if (value != null) onSchemeChanged(value);
                },
          decoration: const InputDecoration(
            labelText: '连接协议',
            prefixIcon: Icon(Icons.security_outlined),
            helperText: 'HTTP 仅适用于可信内网；优先使用 HTTPS。',
          ),
          items: const [
            DropdownMenuItem(value: 'https', child: Text('HTTPS（推荐）')),
            DropdownMenuItem(value: 'http', child: Text('HTTP（可信内网）')),
          ],
        ),
        const SizedBox(height: LumaSpacing.md),
        TextField(
          controller: tokenController,
          enabled: enabled && !controller.isLoading,
          obscureText: true,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: controller.isLoading ? null : (_) => onConnect(),
          decoration: const InputDecoration(
            labelText: '访问令牌',
            prefixIcon: Icon(Icons.key_rounded),
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: !enabled || controller.isLoading ? null : onConnect,
          icon: controller.isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_rounded),
          label: Text(controller.isLoading ? '正在连接' : '立即连接'),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: controller.message == null
              ? const SizedBox(height: LumaSpacing.xl)
              : ConnectionNotice(
                  key: ValueKey(controller.message),
                  phase: controller.phase,
                  message: controller.message!,
                ),
        ),
      ],
    );
  }
}
