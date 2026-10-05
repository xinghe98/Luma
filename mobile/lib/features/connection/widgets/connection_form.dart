import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../shared/layout/adaptive_action_width.dart';
import '../../shell/widgets/tv_field_gate.dart';
import '../connection_controller.dart';
import 'connection_notice.dart';

class ConnectionForm extends StatefulWidget {
  const ConnectionForm({
    super.key,
    required this.controller,
    required this.hostController,
    required this.portController,
    required this.usernameController,
    required this.passwordController,
    required this.enabled,
    this.proxied = false,
    this.television = false,
    this.connectFocusNode,
    required this.onConnect,
  });

  final ConnectionController controller;
  final TextEditingController hostController;
  final TextEditingController portController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool enabled;
  final bool proxied;

  /// TV：字段外层持浏览焦点，OK 才进入编辑；连接按钮在失败后接回焦点。
  final bool television;

  /// 可选的「立即连接」按钮焦点节点；TV 在连接失败后交回该按钮。
  final FocusNode? connectFocusNode;
  final VoidCallback onConnect;

  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  FocusNode? _hostField;
  FocusNode? _portField;
  FocusNode? _usernameField;
  FocusNode? _passwordField;

  /// TV：字段节点不参与方向遍历（浏览焦点落在外层闸门上），
  /// 只经 OK/requestFocus 进入编辑；Next 链由提交回调显式驱动。
  FocusNode _createField(String label) => FocusNode(
    debugLabel: 'connection-field-$label',
    skipTraversal: widget.television,
  );

  FocusNode get _host => _hostField ??= _createField('host');
  FocusNode get _port => _portField ??= _createField('port');
  FocusNode get _username => _usernameField ??= _createField('username');
  FocusNode get _password => _passwordField ??= _createField('password');

  /// TV 显式 Next 链：地址 → 端口 → 用户名 → 密码 → 提交。
  void _submitHost(String value) => _port.requestFocus();
  void _submitPort(String value) => _username.requestFocus();
  void _submitUsername(String value) => _password.requestFocus();

  @override
  void dispose() {
    _hostField?.dispose();
    _portField?.dispose();
    _usernameField?.dispose();
    _passwordField?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TV 焦点顺序：地址 → 端口 → 用户名 → 密码 → 立即连接；代理入口
    // 在 AppBar 上独立可达。Next/Done 沿用既有提交；普通端维持原布局。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _tvField(
                fieldFocusNode: _host,
                child: TextField(
                  controller: widget.hostController,
                  focusNode: _host,
                  autofocus: false,
                  enabled: widget.enabled && !widget.controller.isLoading,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  onSubmitted: widget.television ? _submitHost : null,
                  decoration: const InputDecoration(
                    labelText: 'IP 地址',
                    hintText: '192.168.1.10',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
              ),
            ),
            const SizedBox(width: LumaSpacing.sm),
            Expanded(
              flex: 2,
              child: _tvField(
                fieldFocusNode: _port,
                child: TextField(
                  controller: widget.portController,
                  focusNode: _port,
                  enabled: widget.enabled && !widget.controller.isLoading,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: widget.television ? _submitPort : null,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    hintText: '8080',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: LumaSpacing.md),
        _tvField(
          fieldFocusNode: _username,
          child: TextField(
            controller: widget.usernameController,
            focusNode: _username,
            enabled: widget.enabled && !widget.controller.isLoading,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: widget.television ? _submitUsername : null,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        _tvField(
          fieldFocusNode: _password,
          child: TextField(
            controller: widget.passwordController,
            focusNode: _password,
            enabled: widget.enabled && !widget.controller.isLoading,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: widget.controller.isLoading
                ? null
                : (_) => widget.onConnect(),
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          widget.proxied
              ? '用户名和密码将通过 VMess 通道发送到内网服务器。'
              : '当前服务器使用 HTTP，用户名和密码仅应在可信局域网内传输。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: widget.proxied
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        AdaptiveActionWidth(
          child: FilledButton.icon(
            focusNode: widget.connectFocusNode,
            onPressed: !widget.enabled || widget.controller.isLoading
                ? null
                : widget.onConnect,
            icon: widget.controller.isLoading
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.link_rounded),
            label: Text(widget.controller.isLoading ? '正在连接' : '立即连接'),
          ),
        ),
        AnimatedSwitcher(
          duration: LumaMotion.forContext(context, LumaMotion.normal),
          switchInCurve: LumaMotion.standard,
          switchOutCurve: LumaMotion.standard,
          child: widget.controller.message == null
              ? const SizedBox(height: LumaSpacing.xl)
              : ConnectionNotice(
                  key: ValueKey(widget.controller.message),
                  phase: widget.controller.phase,
                  message: widget.controller.message!,
                ),
        ),
      ],
    );
  }

  /// TV：字段包一层浏览闸门，闸门持焦点时用主色描边提示可进入编辑；
  /// 普通端原样返回，不引入额外焦点层。
  Widget _tvField({required FocusNode fieldFocusNode, required Widget child}) {
    if (!widget.television) return child;
    return TvTextFieldGate(
      fieldFocusNode: fieldFocusNode,
      autofocus: identical(fieldFocusNode, _host),
      builder: (context, gateFocused) =>
          _GateFocusHalo(focused: gateFocused, child: child),
    );
  }
}

/// 闸门浏览焦点的描边；不改字段布局尺寸。
class _GateFocusHalo extends StatelessWidget {
  const _GateFocusHalo({required this.focused, required this.child});

  final Widget child;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: LumaMotion.forContext(context, LumaMotion.fast),
      curve: Curves.easeOutQuart,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LumaRadii.medium),
        border: focused
            ? Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: LumaTvLayout.focusStroke,
              )
            : null,
      ),
      child: child,
    );
  }
}
