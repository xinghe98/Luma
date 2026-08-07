import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../data/proxy/vmess_proxy_controller.dart';
import '../../settings/dialogs/confirmation_dialog.dart';

/// 连接页右上角入口：蓝色文字按钮，状态随代理变化。
class VmessProxyAppBarAction extends StatelessWidget {
  const VmessProxyAppBarAction({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onStart,
    required this.onStop,
    required this.onImport,
    required this.onDelete,
  });

  final VmessProxyController controller;
  final bool enabled;
  final Future<bool> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function(String value) onImport;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final label = controller.isActive ? '代理已开' : '代理';
        return TextButton(
          onPressed: enabled
              ? () => unawaited(
                  showVmessProxyDialog(
                    context,
                    controller: controller,
                    onStart: onStart,
                    onStop: onStop,
                    onImport: onImport,
                    onDelete: onDelete,
                  ),
                )
              : null,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.primary,
            minimumSize: const Size(
              LumaLayout.minTapTarget,
              LumaLayout.minTapTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.sm),
          ),
          child: Text(label),
        );
      },
    );
  }
}

/// Telegram 风格：弹层内粘贴 / 填写 VMess 链接并启停代理。
Future<void> showVmessProxyDialog(
  BuildContext context, {
  required VmessProxyController controller,
  required Future<bool> Function() onStart,
  required Future<void> Function() onStop,
  required Future<void> Function(String value) onImport,
  required Future<void> Function() onDelete,
}) {
  return showDialog<void>(
    context: context,
    animationStyle: AnimationStyle.noAnimation,
    builder: (_) => _VmessProxyDialog(
      controller: controller,
      onStart: onStart,
      onStop: onStop,
      onImport: onImport,
      onDelete: onDelete,
    ),
  );
}

class _VmessProxyDialog extends StatefulWidget {
  const _VmessProxyDialog({
    required this.controller,
    required this.onStart,
    required this.onStop,
    required this.onImport,
    required this.onDelete,
  });

  final VmessProxyController controller;
  final Future<bool> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function(String value) onImport;
  final Future<void> Function() onDelete;

  @override
  State<_VmessProxyDialog> createState() => _VmessProxyDialogState();
}

class _VmessProxyDialogState extends State<_VmessProxyDialog> {
  late final TextEditingController _link;
  var _submitting = false;

  VmessProxyController get _controller => widget.controller;

  bool get _busy {
    final phase = _controller.phase;
    return _submitting ||
        phase == VmessProxyPhase.loading ||
        phase == VmessProxyPhase.starting ||
        phase == VmessProxyPhase.stopping;
  }

  @override
  void initState() {
    super.initState();
    _link = TextEditingController();
    _link.addListener(_onChanged);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _link
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _controller.profile;
    final active = _controller.isActive;
    final stopping = _controller.phase == VmessProxyPhase.stopping;
    final showDisconnect = active || stopping;
    final message = _controller.message;
    final status = _statusText(profile?.displayName, active);

    return AlertDialog(
      scrollable: true,
      title: const Text('连接代理'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '仅代理轻影流量，不影响系统或其他应用。支持单条 VMess 分享链接。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: LumaSpacing.md),
          TextField(
            controller: _link,
            enabled: !_busy && !showDisconnect,
            autofocus: profile == null && !showDisconnect,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'VMess 链接',
              hintText: 'vmess://…',
              alignLabelWithHint: true,
              suffixIcon: IconButton(
                tooltip: '粘贴',
                onPressed: _busy || showDisconnect
                    ? null
                    : () => unawaited(_paste()),
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
            onSubmitted: (_) {
              if (!_busy && !showDisconnect) unawaited(_connect());
            },
          ),
          const SizedBox(height: LumaSpacing.sm),
          Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: LumaSpacing.xs),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: LumaSpacing.md,
      actionsPadding: const EdgeInsets.fromLTRB(
        LumaSpacing.sm,
        0,
        LumaSpacing.sm,
        LumaSpacing.sm,
      ),
      buttonPadding: const EdgeInsets.symmetric(horizontal: LumaSpacing.sm),
      actions: [
        if (profile != null && !showDisconnect)
          TextButton(
            style: _actionStyle(),
            onPressed: _busy ? null : () => unawaited(_delete()),
            child: const Text('删除'),
          ),
        TextButton(
          style: _actionStyle(),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (showDisconnect)
          FilledButton(
            style: _filledStyle(),
            onPressed: _busy ? null : () => unawaited(_disconnect()),
            child: Text(stopping || _submitting ? '关闭中…' : '关闭代理'),
          )
        else
          FilledButton(
            style: _filledStyle(),
            onPressed: _busy ? null : () => unawaited(_connect()),
            child: Text(_primaryLabel),
          ),
      ],
    );
  }

  String get _primaryLabel {
    if (_controller.phase == VmessProxyPhase.starting) return '连接中…';
    if (_controller.phase == VmessProxyPhase.loading) return '处理中…';
    if (_controller.phase == VmessProxyPhase.failure) return '重试';
    if (_link.text.trim().isNotEmpty) return '连接';
    if (_controller.profile != null) return '启动代理';
    return '连接';
  }

  String _statusText(String? displayName, bool active) {
    if (active) return '已连接 · ${displayName ?? 'VMess'}';
    return switch (_controller.phase) {
      VmessProxyPhase.starting => '正在连接…',
      VmessProxyPhase.stopping => '正在关闭…',
      VmessProxyPhase.loading => '正在处理…',
      _ when displayName != null => '已保存 · $displayName · 未启动',
      _ => '未配置代理',
    };
  }

  ButtonStyle _actionStyle() => TextButton.styleFrom(
    minimumSize: const Size(LumaLayout.minTapTarget, LumaLayout.minTapTarget),
    padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.xs),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  ButtonStyle _filledStyle() => FilledButton.styleFrom(
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(
      horizontal: LumaSpacing.sm,
      vertical: LumaSpacing.xxs,
    ),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    setState(() {
      _link.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  Future<void> _connect() async {
    if (_busy || _controller.isActive) return;
    final typed = _link.text.trim();
    setState(() => _submitting = true);
    try {
      if (typed.isNotEmpty) {
        await widget.onImport(typed);
        if (_controller.phase == VmessProxyPhase.failure) return;
      } else if (_controller.profile == null) {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final clip = data?.text?.trim() ?? '';
        if (clip.isEmpty) {
          await widget.onImport('');
          return;
        }
        await widget.onImport(clip);
        if (_controller.phase == VmessProxyPhase.failure) return;
      }

      final started = await widget.onStart();
      if (!mounted) return;
      if (started || _controller.isActive) {
        _link.clear();
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;
    setState(() => _submitting = true);
    try {
      await widget.onStop();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || _controller.isActive) return;
    final confirmed = await showConfirmationDialog(
      context,
      title: '删除代理配置？',
      message: '删除后需要重新填写 VMess 分享链接。',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;
    setState(() => _submitting = true);
    try {
      await widget.onDelete();
      if (mounted) _link.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
