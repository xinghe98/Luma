import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../data/services/connection_service.dart';
import '../../data/storage/connection_form_store.dart';
import '../../shared/interaction/tv_key_bindings.dart';
import '../../shared/layout/tv_content_frame.dart';
import 'connection_controller.dart';

import 'widgets/connection_brand_header.dart';
import 'widgets/connection_form.dart';
import 'widgets/vmess_proxy_control.dart';
import 'widgets/tv_connection_layout.dart';

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
  final _connectButtonFocus = FocusNode(debugLabel: 'connection-connect');
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
    _connectButtonFocus.dispose();
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
    _splitPastedAddress();
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
    if (connected) {
      await dependencies.rememberConnectionForm(
        SavedConnectionForm(host: host, port: port, username: username),
      );
      return;
    }
    // TV：等失败态重新启用按钮后再交回焦点，保留输入便于修改或重试。
    if (mounted && dependencies.deviceProfile.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            dependencies.isDisposed ||
            dependencies.connection.phase != ConnectionPhase.failure) {
          return;
        }
        _connectButtonFocus.requestFocus();
      });
    }
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
        final isTelevision = dependencies.deviceProfile.isTelevision;
        final connectionForm = ConnectionForm(
          controller: controller,
          hostController: _host,
          portController: _port,
          usernameController: _username,
          passwordController: _password,
          proxied: proxy?.isActive ?? false,
          enabled: !restoring,
          television: isTelevision,
          connectFocusNode: isTelevision ? _connectButtonFocus : null,
          onConnect: () {
            // ignore: discarded_futures
            _connect();
          },
        );
        final proxyAction = proxy == null
            ? null
            : VmessProxyAppBarAction(
                controller: proxy,
                enabled: dependencies.canConfigureProxy,
                onStart: dependencies.startProxy,
                onStop: dependencies.stopProxy,
                onImport: dependencies.importProxyProfile,
                onDelete: dependencies.deleteProxyProfile,
              );
        if (isTelevision) {
          return Scaffold(
            body: SafeArea(
              child: TvKeyBindings(
                child: TvContentFrame(
                  maxWidth: LumaTvLayout.contentMaxWidth,
                  child: TvConnectionLayout(
                    proxyAction: proxyAction,
                    form: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        connectionForm,
                        if (restoring) const Text('正在恢复已保存的服务器连接…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        final form = SingleChildScrollView(
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
                        connectionForm,
                        if (restoring) ...[
                          const SizedBox(height: LumaSpacing.sm),
                          const Text('正在恢复已保存的服务器连接…'),
                        ],
                        const SizedBox(height: LumaSpacing.lg),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final body = SafeArea(child: form);
        return Scaffold(
          appBar: proxyAction == null
              ? null
              : AppBar(
                  automaticallyImplyLeading: false,
                  actions: [proxyAction],
                ),
          body: body,
        );
      },
    );
  }

  /// 提交前把粘贴的 http(s)://host:port 或 host:port 拆回地址与端口两个字段。
  /// 用户粘贴完整地址时无需手动分段输入。
  void _splitPastedAddress() {
    final address = _host.text.trim();
    if (address.isEmpty) return;
    final parsed = _splitAddress(address);
    if (parsed == null) return;
    _host.value = TextEditingValue(
      text: parsed.host,
      selection: TextSelection.collapsed(offset: parsed.host.length),
    );
    if (parsed.port.isEmpty) return;
    _port.value = TextEditingValue(
      text: parsed.port,
      selection: TextSelection.collapsed(offset: parsed.port.length),
    );
  }

  /// 只拆分带协议或端口的地址；纯主机名返回 null，避免覆盖用户填写的端口。
  /// 端口段不是 1–65535 的数字时也返回 null，交给字段校验提示。
  static ({String host, String port})? _splitAddress(String address) {
    final value = address.trim();
    final hasScheme = RegExp(
      r'^https?://',
      caseSensitive: false,
    ).hasMatch(value);
    final uri = hasScheme ? Uri.tryParse(value) : Uri.tryParse('http://$value');
    if (uri == null || uri.host.isEmpty) return null;
    if (!uri.hasPort) {
      return hasScheme ? (host: uri.host, port: '') : null;
    }
    return (host: uri.host, port: '${uri.port}');
  }
}
