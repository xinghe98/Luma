import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../data/proxy/vmess_proxy_controller.dart';
import '../../../shared/layout/surface_card.dart';
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

/// 代理弹窗：未配置时粘贴链接；已保存时展示配置卡并一键启停，避免再次粘贴的误解。
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
  var _replacing = false;

  VmessProxyController get _controller => widget.controller;

  bool get _busy {
    final phase = _controller.phase;
    return _submitting ||
        phase == VmessProxyPhase.loading ||
        phase == VmessProxyPhase.starting ||
        phase == VmessProxyPhase.stopping;
  }

  bool get _hasSavedProfile => _controller.profile != null;

  bool get _showLinkEditor => !_hasSavedProfile || _replacing;

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
    if (!mounted) return;
    // 删除配置后回到首次录入态。
    if (!_hasSavedProfile && _replacing) {
      _replacing = false;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _controller.profile;
    final active = _controller.isActive;
    final showDisconnect =
        active || _controller.phase == VmessProxyPhase.stopping;
    final message = _controller.message;
    final muted = theme.colorScheme.onSurfaceVariant;

    return AlertDialog(
      scrollable: true,
      title: Text(_dialogTitle(showDisconnect: showDisconnect)),
      titlePadding: const EdgeInsets.fromLTRB(
        LumaSpacing.lg,
        LumaSpacing.lg,
        LumaSpacing.lg,
        LumaSpacing.xs,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        LumaSpacing.lg,
        LumaSpacing.sm,
        LumaSpacing.lg,
        LumaSpacing.md,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_hasSavedProfile && !_replacing) ...[
            Text(
              '仅代理轻影流量。粘贴一条 VMess 分享链接即可。',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: LumaSpacing.sm),
          ],
          if (_hasSavedProfile && !_replacing)
            _SavedProfileCard(
              displayName: profile!.displayName,
              statusLabel: _statusLabel(active: active),
              active: active,
              busy: _busy,
            ),
          if (_showLinkEditor) ...[
            if (_hasSavedProfile && _replacing) ...[
              Text(
                '粘贴新链接以替换当前节点。',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(height: LumaSpacing.xs),
            ],
            TextField(
              controller: _link,
              enabled: !_busy && !showDisconnect,
              autofocus: !_hasSavedProfile && !showDisconnect,
              minLines: 1,
              maxLines: 3,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                labelText: _hasSavedProfile ? '新的 VMess 链接' : 'VMess 链接',
                hintText: 'vmess://…',
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  tooltip: '粘贴',
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy || showDisconnect
                      ? null
                      : () => unawaited(_paste()),
                  icon: const Icon(Icons.content_paste_rounded),
                ),
              ),
              onSubmitted: (_) {
                if (_busy || showDisconnect) return;
                unawaited(_replacing ? _replaceAndStart() : _connect());
              },
            ),
          ],
          if (message != null) ...[
            const SizedBox(height: LumaSpacing.xs),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: LumaSpacing.sm),
          ..._buildActionColumn(showDisconnect: showDisconnect),
        ],
      ),
      // 操作排在 content 内，避免 AlertDialog actions 横向挤占。
      actions: const [],
    );
  }

  /// 主按钮紧凑全宽；次级操作单行文字按钮，减少纵向占用。
  List<Widget> _buildActionColumn({required bool showDisconnect}) {
    final primary = showDisconnect
        ? FilledButton(
            style: _primaryStyle(),
            onPressed: _busy ? null : () => unawaited(_disconnect()),
            child: Text(_disconnectLabel),
          )
        : _replacing
        ? FilledButton(
            style: _primaryStyle(),
            onPressed: _busy || _link.text.trim().isEmpty
                ? null
                : () => unawaited(_replaceAndStart()),
            child: Text(_replaceLabel),
          )
        : FilledButton(
            style: _primaryStyle(),
            onPressed: _busy ? null : () => unawaited(_onPrimaryPressed()),
            child: Text(_primaryLabel),
          );

    final secondary = <Widget>[
      if (showDisconnect)
        TextButton(
          style: _secondaryStyle(),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        )
      else if (_replacing)
        TextButton(
          style: _secondaryStyle(),
          onPressed: _busy
              ? null
              : () => setState(() {
                  _replacing = false;
                  _link.clear();
                }),
          child: const Text('返回'),
        )
      else if (_hasSavedProfile) ...[
        TextButton(
          style: _secondaryStyle(),
          onPressed: _busy
              ? null
              : () => setState(() {
                  _replacing = true;
                  _link.clear();
                }),
          child: const Text('更换节点'),
        ),
        TextButton(
          style: _secondaryStyle(),
          onPressed: _busy ? null : () => unawaited(_delete()),
          child: const Text('删除'),
        ),
        TextButton(
          style: _secondaryStyle(),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ] else
        TextButton(
          style: _secondaryStyle(),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
    ];

    return [
      primary,
      if (secondary.isNotEmpty) ...[
        const SizedBox(height: LumaSpacing.xxs),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: LumaSpacing.xxs,
          runSpacing: 0,
          children: secondary,
        ),
      ],
    ];
  }

  String get _disconnectLabel {
    final stopping = _controller.phase == VmessProxyPhase.stopping;
    return stopping || _submitting ? '关闭中…' : '关闭代理';
  }

  String _dialogTitle({required bool showDisconnect}) {
    if (showDisconnect) return '代理运行中';
    if (_hasSavedProfile && !_replacing) return '已保存的代理';
    if (_replacing) return '更换代理节点';
    return '连接代理';
  }

  String get _primaryLabel {
    if (_controller.phase == VmessProxyPhase.starting) return '启动中…';
    if (_controller.phase == VmessProxyPhase.loading) return '处理中…';
    if (_controller.phase == VmessProxyPhase.failure) {
      return switch (_failureKind) {
        _ProxyFailureKind.stop => '重试关闭',
        _ProxyFailureKind.delete => '重试删除',
        _ProxyFailureKind.start || _ProxyFailureKind.other =>
          _hasSavedProfile ? '重新启动' : '重试',
      };
    }
    if (_hasSavedProfile) return '启动代理';
    return '保存并启动';
  }

  _ProxyFailureKind get _failureKind {
    final message = _controller.message;
    if (message == VmessProxyController.stopFailureMessage) {
      return _ProxyFailureKind.stop;
    }
    if (message != null && message.contains('删除失败')) {
      return _ProxyFailureKind.delete;
    }
    if (message == VmessProxyController.failureMessage ||
        (message != null && message.contains('导入'))) {
      return _ProxyFailureKind.start;
    }
    return _ProxyFailureKind.other;
  }

  String get _replaceLabel {
    if (_controller.phase == VmessProxyPhase.starting ||
        _controller.phase == VmessProxyPhase.loading) {
      return '处理中…';
    }
    return '保存并启动';
  }

  String _statusLabel({required bool active}) {
    if (active) return '运行中';
    return switch (_controller.phase) {
      VmessProxyPhase.starting => '正在启动…',
      VmessProxyPhase.stopping => '正在关闭…',
      VmessProxyPhase.loading => '正在处理…',
      VmessProxyPhase.failure => _failureStatusLabel,
      _ => '已保存，可直接启动',
    };
  }

  /// 失败态按 controller 消息区分启停/删除，避免一律写成“启动失败”。
  String get _failureStatusLabel => switch (_failureKind) {
    _ProxyFailureKind.stop => '关闭失败 · 可重试',
    _ProxyFailureKind.delete => '删除失败 · 可重试',
    _ProxyFailureKind.start || _ProxyFailureKind.other =>
      _controller.message != null && _controller.message!.contains('导入')
          ? '配置无效 · 可重试'
          : '启动失败 · 可重试',
  };

  ButtonStyle _primaryStyle() => FilledButton.styleFrom(
    minimumSize: const Size(double.infinity, LumaLayout.buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  ButtonStyle _secondaryStyle() => TextButton.styleFrom(
    minimumSize: const Size(0, LumaLayout.compactControlHeight),
    padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.xs),
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

  Future<void> _onPrimaryPressed() async {
    if (_controller.phase == VmessProxyPhase.failure) {
      switch (_failureKind) {
        case _ProxyFailureKind.stop:
          await _disconnect();
          return;
        case _ProxyFailureKind.delete:
          await _delete();
          return;
        case _ProxyFailureKind.start:
        case _ProxyFailureKind.other:
          break;
      }
    }
    await _connect();
  }

  Future<void> _connect() async {
    if (_busy || _controller.isActive) return;
    final typed = _link.text.trim();
    setState(() => _submitting = true);
    try {
      if (!_hasSavedProfile) {
        if (typed.isNotEmpty) {
          await widget.onImport(typed);
          if (_controller.phase == VmessProxyPhase.failure) return;
        } else {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          final clip = data?.text?.trim() ?? '';
          if (clip.isEmpty) {
            await widget.onImport('');
            return;
          }
          await widget.onImport(clip);
          if (_controller.phase == VmessProxyPhase.failure) return;
        }
      }

      final started = await widget.onStart();
      if (!mounted) return;
      if (started || _controller.isActive) {
        _link.clear();
        _replacing = false;
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _replaceAndStart() async {
    if (_busy || _controller.isActive) return;
    final typed = _link.text.trim();
    if (typed.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onImport(typed);
      if (_controller.phase == VmessProxyPhase.failure) return;
      final started = await widget.onStart();
      if (!mounted) return;
      if (started || _controller.isActive) {
        _link.clear();
        _replacing = false;
        Navigator.pop(context);
      } else if (mounted) {
        setState(() => _replacing = false);
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
      if (mounted) {
        _link.clear();
        _replacing = false;
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _SavedProfileCard extends StatelessWidget {
  const _SavedProfileCard({
    required this.displayName,
    required this.statusLabel,
    required this.active,
    required this.busy,
  });

  final String displayName;
  final String statusLabel;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = active ? scheme.primary : scheme.onSurfaceVariant;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: LumaSpacing.sm,
        vertical: LumaSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.shield_rounded : Icons.shield_moon_outlined,
                size: LumaIconSize.status,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: LumaSpacing.xs),
              Expanded(
                child: Text(
                  displayName,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            statusLabel,
            style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
          ),
          if (busy) ...[
            const SizedBox(height: LumaSpacing.xs),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }
}

enum _ProxyFailureKind { start, stop, delete, other }
