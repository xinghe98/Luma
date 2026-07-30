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
    required this.usernameController,
    required this.passwordController,
    required this.enabled,
    required this.onConnect,
  });

  final ConnectionController controller;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool enabled;
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
        const SizedBox(height: LumaSpacing.md),
        TextField(
          controller: usernameController,
          enabled: enabled && !controller.isLoading,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: '用户名',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        TextField(
          controller: passwordController,
          enabled: enabled && !controller.isLoading,
          obscureText: true,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: controller.isLoading ? null : (_) => onConnect(),
          decoration: const InputDecoration(
            labelText: '密码',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          '当前服务器使用 HTTP，用户名和密码仅应在可信局域网内传输。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        FilledButton.icon(
          onPressed: !enabled || controller.isLoading ? null : onConnect,
          icon: controller.isLoading
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : const Icon(Icons.link_rounded),
          label: Text(controller.isLoading ? '正在连接' : '立即连接'),
        ),
        AnimatedSwitcher(
          duration: LumaMotion.forContext(context, LumaMotion.normal),
          switchInCurve: LumaMotion.standard,
          switchOutCurve: LumaMotion.standard,
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
