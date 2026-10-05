// TV 文本字段闸门：遥控器浏览时焦点落在字段外层，OK 才进入 TextField 编辑
// 并弹出系统 IME；编辑态按 Back（系统返回或 Esc）先退回字段外层，再次 Back
// 才交给路由关闭。供连接表单、搜索输入与 TV 弹窗字段复用，不改变既有提交回调。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// [fieldFocusNode] 为受控 TextField 的焦点节点；[builder] 的 focused 参数
/// 表示当前是外层浏览焦点（用于给字段绘制聚焦描边）。
class TvTextFieldGate extends StatefulWidget {
  const TvTextFieldGate({
    super.key,
    required this.fieldFocusNode,
    required this.builder,
    this.autofocus = false,
  });

  final FocusNode fieldFocusNode;
  final Widget Function(BuildContext context, bool focused) builder;

  /// 进入页面时是否自动聚焦外层闸门；只影响浏览焦点，不会弹出 IME。
  final bool autofocus;

  /// 壳层拦截系统 Back 时，先退出当前分支的字段编辑；未编辑时返回 false。
  static bool exitFocusedEditing() {
    final context = FocusManager.instance.primaryFocus?.context;
    final state = context?.findAncestorStateOfType<_TvTextFieldGateState>();
    if (state == null || !state.widget.fieldFocusNode.hasFocus) return false;
    state._gate.requestFocus();
    return true;
  }

  @override
  State<TvTextFieldGate> createState() => _TvTextFieldGateState();
}

class _TvTextFieldGateState extends State<TvTextFieldGate> {
  late final FocusNode _gate;
  var _fieldHadFocus = false;

  @override
  void initState() {
    super.initState();
    _gate = FocusNode(debugLabel: 'tv-field-gate');
    widget.fieldFocusNode.addListener(_onFieldFocusChanged);
  }

  @override
  void didUpdateWidget(TvTextFieldGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldFocusNode != widget.fieldFocusNode) {
      oldWidget.fieldFocusNode.removeListener(_onFieldFocusChanged);
      widget.fieldFocusNode.addListener(_onFieldFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.fieldFocusNode.removeListener(_onFieldFocusChanged);
    _gate.dispose();
    super.dispose();
  }

  /// 字段失去焦点后，若焦点被系统还给了匿名 scope（IME 关闭、卡片卸载），
  /// 则把焦点接回外层闸门；移动到其他字段或按钮时不接管。
  void _onFieldFocusChanged() {
    if (widget.fieldFocusNode.hasFocus) {
      _fieldHadFocus = true;
      return;
    }
    if (!_fieldHadFocus) return;
    _fieldHadFocus = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 先落实本帧提交回调的焦点请求，避免把刚交给结果卡片的焦点抢回字段。
      FocusManager.instance.applyFocusChangesIfNeeded();
      final primary = FocusManager.instance.primaryFocus;
      final claimed =
          primary != null && primary != _gate && primary is! FocusScopeNode;
      if (!claimed) _gate.requestFocus();
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isConfirm =
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (widget.fieldFocusNode.hasFocus) {
      // 编辑态：确认键交给输入框/IME 自身处理（提交、换行），闸门不截获；
      // Back 先退回字段外层并收起 IME，不关闭页面。
      if (isConfirm) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        _gate.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (isConfirm && _gate.hasPrimaryFocus) {
      // 仅闸门自身的 OK 进入编辑；后缀按钮继续接收自己的激活动作。
      widget.fieldFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_gate, widget.fieldFocusNode]),
      builder: (context, _) {
        final editing = widget.fieldFocusNode.hasFocus;
        // 系统返回键不产生按键事件：编辑态由 PopScope 拦截所在路由的
        // maybePop，先退回外层闸门，第二次 Back 才按原语义关闭页面。
        return PopScope(
          canPop: !editing,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && editing) _gate.requestFocus();
          },
          child: Focus(
            focusNode: _gate,
            autofocus: widget.autofocus,
            onKeyEvent: _onKeyEvent,
            child: widget.builder(context, _gate.hasFocus),
          ),
        );
      },
    );
  }
}
