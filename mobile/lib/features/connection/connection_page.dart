import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/services/connection_service.dart';
import '../../data/storage/connection_form_store.dart';
import 'connection_controller.dart';

import 'widgets/connection_brand_header.dart';
import 'widgets/connection_form.dart';
import 'widgets/recent_servers.dart';
import 'widgets/vmess_proxy_control.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8080');
  final _username = TextEditingController();
  final _password = TextEditingController();
  static const _connectionScheme = 'http';
  var _formHydrated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_formHydrated) return;
    _formHydrated = true;
    _hydrateSavedForm();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 内置服务器仅提供 HTTP，连接页无需让用户选择协议。
  String get _serverAddress {
    final host = _host.text.trim();
    final port = _port.text.trim();
    if (host.isEmpty) return '';
    if (port.isEmpty) return '$_connectionScheme://$host';
    return '$_connectionScheme://$host:$port';
  }

  Future<void> _hydrateSavedForm() async {
    final saved = await AppScope.of(context).loadSavedConnectionForm();
    if (!mounted || saved == null) return;
    // 用户已开始输入时不覆盖。
    if (_host.text.trim().isNotEmpty ||
        _username.text.trim().isNotEmpty ||
        (_port.text.trim().isNotEmpty && _port.text.trim() != '8080')) {
      return;
    }
    setState(() {
      _host.value = TextEditingValue(
        text: saved.host,
        selection: TextSelection.collapsed(offset: saved.host.length),
      );
      _port.value = TextEditingValue(
        text: saved.port.isEmpty ? '8080' : saved.port,
        selection: TextSelection.collapsed(
          offset: (saved.port.isEmpty ? '8080' : saved.port).length,
        ),
      );
      _username.value = TextEditingValue(
        text: saved.username,
        selection: TextSelection.collapsed(offset: saved.username.length),
      );
    });
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    final dependencies = AppScope.of(context);
    final host = _host.text.trim();
    final port = _port.text.trim();
    final username = _username.text.trim();
    await dependencies.connection.connect(
      _serverAddress,
      LoginCredentials(username: _username.text, password: _password.text),
    );
    // 成功后路由可能已卸载连接页，表单记忆不依赖 mounted。
    if (dependencies.isDisposed || host.isEmpty) return;
    final connected =
        dependencies.session.isConnected ||
        dependencies.connection.phase == ConnectionPhase.success;
    if (!connected) return;
    await dependencies.rememberConnectionForm(
      SavedConnectionForm(host: host, port: port, username: username),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = AppScope.of(context);
    final controller = dependencies.connection;
    final proxy = dependencies.proxy;
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        dependencies.restoring,
        ?proxy,
      ]),
      builder: (context, _) {
        final restoring = dependencies.restoring.value;
        return Scaffold(
          appBar: proxy == null
              ? null
              : AppBar(
                  automaticallyImplyLeading: false,
                  actions: [
                    VmessProxyAppBarAction(
                      controller: proxy,
                      enabled: dependencies.canConfigureProxy,
                      onStart: dependencies.startProxy,
                      onStop: dependencies.stopProxy,
                      onImport: dependencies.importProxyProfile,
                      onDelete: dependencies.deleteProxyProfile,
                    ),
                  ],
                ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: LumaLayout.formMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ConnectionBrandHeader(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          LumaSpacing.lg,
                          LumaSpacing.xl,
                          LumaSpacing.lg,
                          LumaSpacing.lg,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ConnectionForm(
                              controller: controller,
                              hostController: _host,
                              portController: _port,
                              usernameController: _username,
                              passwordController: _password,
                              proxied: proxy?.isActive ?? false,
                              enabled: !restoring,
                              onConnect: () {
                                // ignore: discarded_futures
                                _connect();
                              },
                            ),
                            if (restoring) ...[
                              const SizedBox(height: LumaSpacing.sm),
                              const Text('正在恢复已保存的服务器连接…'),
                            ],
                            const SizedBox(height: LumaSpacing.lg),
                            RecentServers(
                              enabled: !restoring && !controller.isLoading,
                              onSelect: _selectServer,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectServer(RecentServer server) {
    final parsed = _parseAddress(server.address);
    setState(() {
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

  static ({String host, String port}) _parseAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri != null && uri.host.isNotEmpty) {
      return (host: uri.host, port: uri.hasPort ? '${uri.port}' : '8080');
    }
    final bare = address.trim().replaceFirst(RegExp(r'^https?://'), '');
    final parts = bare.split(':');
    if (parts.length >= 2) {
      return (host: parts.first, port: parts.sublist(1).join(':'));
    }
    return (host: bare, port: '8080');
  }
}
