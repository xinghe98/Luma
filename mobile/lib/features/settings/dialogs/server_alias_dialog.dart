import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../shared/interaction/tv_key_bindings.dart';
import '../../shell/widgets/tv_field_gate.dart';
import 'tv_field_halo.dart';

/// 打开服务器别名编辑框；取消返回 null，恢复默认返回空字符串。
Future<String?> showServerAliasDialog(
  BuildContext context,
  String currentName,
) => showDialog<String>(
  context: context,
  // 编辑取消后立即移除遮罩和阴影，避免键盘收起时留下退场残影。
  animationStyle: AnimationStyle.noAnimation,
  builder: (_) => _ServerAliasDialog(currentName: currentName),
);

class _ServerAliasDialog extends StatefulWidget {
  const _ServerAliasDialog({required this.currentName});

  final String currentName;

  @override
  State<_ServerAliasDialog> createState() => _ServerAliasDialogState();
}

class _ServerAliasDialogState extends State<_ServerAliasDialog> {
  late final TextEditingController _controller;
  FocusNode? _fieldFocusNode;
  bool? _isTelevision;

  bool get isTelevision => _isTelevision ?? false;

  /// TV：字段焦点节点不参与方向遍历，浏览焦点在 TvTextFieldGate 闸门上；
  /// 普通端不注入节点，保持系统默认行为。
  FocusNode get _fieldFocus => _fieldFocusNode ??= FocusNode(
    debugLabel: 'server-alias-field',
    skipTraversal: isTelevision,
  );

  /// TV 按钮最小高度 56，普通端沿用 40 的紧凑布局。
  double get _buttonHeight =>
      isTelevision ? LumaTvLayout.controlMinHeight : LumaLayout.buttonHeight;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 独立嵌入时沿用普通端交互；应用内由 AppScope 提供设备形态。
    _isTelevision ??=
        AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false;
  }

  @override
  void dispose() {
    _fieldFocusNode?.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildField() {
    final field = TextField(
      controller: _controller,
      focusNode: isTelevision ? _fieldFocus : null,
      // TV 由闸门持浏览焦点，OK 才进入编辑弹出 IME；普通端保持自动聚焦。
      autofocus: !isTelevision,
      textInputAction: isTelevision ? TextInputAction.done : null,
      onSubmitted: isTelevision
          ? (_) => Navigator.pop(context, _controller.text)
          : null,
      maxLength: 80,
      decoration: const InputDecoration(
        labelText: '服务器名称',
        helperText: '仅保存在此设备',
      ),
    );
    if (!isTelevision) return field;
    return TvTextFieldGate(
      // 打开弹窗即落在字段闸门，方向键向下可达操作按钮。
      autofocus: true,
      fieldFocusNode: _fieldFocus,
      builder: (context, focused) =>
          TvFieldHalo(focused: focused, child: field),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = _buildActions();
    if (isTelevision) {
      return TvKeyBindings(
        child: AlertDialog(
          constraints: const BoxConstraints(minWidth: 480, maxWidth: 640),
          insetPadding: const EdgeInsets.all(LumaSpacing.lg),
          scrollable: true,
          title: const Text('服务器别名'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildField(),
              const SizedBox(height: LumaSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: LumaSpacing.xs,
                runSpacing: LumaSpacing.xs,
                children: actions,
              ),
            ],
          ),
        ),
      );
    }
    return AlertDialog(
      scrollable: true,
      title: const Text('服务器别名'),
      content: _buildField(),
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: LumaSpacing.xs,
      actions: actions,
    );
  }

  List<Widget> _buildActions() => [
    TextButton(
      style: TextButton.styleFrom(
        minimumSize: Size(0, _buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.sm),
        visualDensity: VisualDensity.standard,
      ),
      onPressed: () => Navigator.pop(context, ''),
      child: const Text('恢复默认'),
    ),
    TextButton(
      style: TextButton.styleFrom(
        minimumSize: Size(0, _buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.sm),
        visualDensity: VisualDensity.standard,
      ),
      onPressed: () => Navigator.pop(context),
      child: const Text('取消'),
    ),
    FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: Size(0, _buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
        visualDensity: VisualDensity.standard,
      ),
      onPressed: () => Navigator.pop(context, _controller.text),
      child: const Text('保存'),
    ),
  ];
}
