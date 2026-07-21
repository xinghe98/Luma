import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../shared/branding/brand_mark.dart';
import 'widgets/connection_form.dart';
import 'widgets/recent_servers.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8080');
  final _token = TextEditingController();
  String _scheme = 'https';

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  /// 由用户选择协议，避免把 HTTPS 历史服务器无声降级为 HTTP。
  String get _serverAddress {
    final host = _host.text.trim();
    final port = _port.text.trim();
    if (host.isEmpty) return '';
    if (port.isEmpty) return '$_scheme://$host';
    return '$_scheme://$host:$port';
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).connection;
    final restoring = AppScope.of(context).restoring.value;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(LumaSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LumaLayout.formMaxWidth,
              ),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BrandMark(),
                    ),
                    const SizedBox(height: LumaSpacing.xxl),
                    Text(
                      '连接你的轻影服务器',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: LumaSpacing.sm),
                    Text(
                      '连接家庭服务器后，你的影像仍然只属于自己的网络。',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: LumaSpacing.xl),
                    ConnectionForm(
                      controller: controller,
                      hostController: _host,
                      portController: _port,
                      tokenController: _token,
                      scheme: _scheme,
                      enabled: !restoring,
                      onSchemeChanged: (value) => setState(() => _scheme = value),
                      onConnect: () {
                        FocusScope.of(context).unfocus();
                        controller.connect(_serverAddress, _token.text);
                      },
                    ),
                    if (restoring) ...[
                      const SizedBox(height: LumaSpacing.sm),
                      const Text('正在恢复已保存的服务器连接…'),
                    ],
                    const SizedBox(height: LumaSpacing.lg),
                    RecentServers(
                      enabled: !controller.isLoading,
                      onSelect: _selectServer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectServer(RecentServer server) {
    final parsed = _parseAddress(server.address);
    setState(() {
      _scheme = parsed.scheme;
      _host.value = TextEditingValue(
        text: parsed.host,
        selection: TextSelection.collapsed(offset: parsed.host.length),
      );
      _port.value = TextEditingValue(
        text: parsed.port,
        selection: TextSelection.collapsed(offset: parsed.port.length),
      );
    });
    context.showLumaSnack('已填入 ${server.name}');
  }

  static ({String scheme, String host, String port}) _parseAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri != null && uri.host.isNotEmpty) {
      final port = uri.hasPort
          ? '${uri.port}'
          : (uri.scheme == 'https' ? '443' : '80');
      return (scheme: uri.scheme, host: uri.host, port: port);
    }
    final bare = address.trim().replaceFirst(RegExp(r'^https?://'), '');
    final parts = bare.split(':');
    if (parts.length >= 2) {
      return (scheme: 'http', host: parts.first, port: parts.sublist(1).join(':'));
    }
    return (scheme: 'http', host: bare, port: '8080');
  }
}
