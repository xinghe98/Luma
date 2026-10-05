// TV 列表焦点集合：为一个货架或规则网格维护方向键移动、离屏目标滚动交接与失焦恢复。
// 只管理本列表的逻辑索引与已挂载焦点节点；列表边界交给 Flutter 默认方向遍历，
// 不建立全局焦点仓库，普通端不使用本组件。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TvFocusCollectionScope 供带 focusId 的 LumaFocusableSurface 找到所属集合。
abstract interface class TvFocusCollectionScope {
  /// 集合内卡片挂载时注册自己的焦点节点；节点随卡片卸载注销并释放。
  void registerFocusItem(String id, FocusNode node);

  /// 卡片卸载时注销；重复或过期注销必须安全。
  void unregisterFocusItem(String id, FocusNode node);

  /// maybeOf 返回最近的外层集合；不在 TV 列表内时返回 null。
  static TvFocusCollectionScope? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_TvFocusCollectionScope>()
      ?.state;
}

class _TvFocusCollectionScope extends InheritedWidget {
  const _TvFocusCollectionScope({required this.state, required super.child});

  final _TvFocusCollectionState state;

  @override
  bool updateShouldNotify(_TvFocusCollectionScope oldWidget) => false;
}

/// TvFocusCollection 为一个横向货架（columns=1）或纵向规则网格提供
/// 遥控器方向键导航：左右移动相邻项，上下按列数移动；目标未挂载时先经
/// [revealIndex] 滚入视口，下一帧再移交焦点。
///
/// 列表内不环绕；到达边界时按键冒泡给默认方向遍历，焦点可移向工具栏、
/// 导航或下一分区。快速重复按键只保留最新目标，页面卸载、筛选变化或
/// 弹窗打开会取消未完成的交接。
class TvFocusCollection extends StatefulWidget {
  const TvFocusCollection({
    super.key,
    required this.itemIds,
    required this.axis,
    required this.columns,
    required this.revealIndex,
    required this.child,
  }) : assert(columns >= 1);

  /// 当前列表项目的稳定 ID，顺序与可见顺序一致；刷新后可增删改。
  final List<String> itemIds;

  /// 货架为 Axis.horizontal，规则网格为 Axis.vertical。
  final Axis axis;

  /// 网格列数；横向货架固定为 1。
  final int columns;

  /// 把 [index] 对应的项目滚到可构建区域；由页面按固定行高/卡宽计算偏移。
  final Future<void> Function(int index) revealIndex;

  final Widget child;

  @override
  State<TvFocusCollection> createState() => _TvFocusCollectionState();
}

class _TvFocusCollectionState extends State<TvFocusCollection>
    implements TvFocusCollectionScope {
  final FocusNode _keyNode = FocusNode();
  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  final Map<FocusNode, VoidCallback> _focusListeners = {};

  String? _lastFocusId;
  int _lastIndex = -1;

  /// 移动中的逻辑位置：快速连续按键从虚拟位置继续，而不是等焦点落地。
  int? _virtualIndex;
  int _moveGeneration = 0;
  int _restoreGeneration = 0;

  int get _rowCount => widget.axis == Axis.horizontal
      ? 1
      : (widget.itemIds.length + widget.columns - 1) ~/ widget.columns;

  @override
  void registerFocusItem(String id, FocusNode node) {
    _nodes[id] = node;
    final previousListener = _focusListeners.remove(node);
    if (previousListener != null) node.removeListener(previousListener);
    void listener() => _onItemFocusChanged(id, node);
    _focusListeners[node] = listener;
    node.addListener(listener);
    // 元素复用时节点可能已持焦，不会再发通知；立即同步当前可见身份。
    _onItemFocusChanged(id, node);
  }

  @override
  void unregisterFocusItem(String id, FocusNode node) {
    if (_nodes[id] == node) _nodes.remove(id);
    final listener = _focusListeners.remove(node);
    if (listener != null) node.removeListener(listener);
    // 最后焦点项卸载：系统把焦点还给外层路由 scope 的时机不稳定（当帧、
    // 次帧或为 null），分别在下一帧重试确认落点后恢复。元素复用或路由
    // 跳转时检查自然落空。
    if (id == _lastFocusId) {
      if (widget.itemIds.isEmpty) {
        _exitWhenEmpty();
      } else {
        _scheduleRestoreIfFocusRevertedToAncestor();
      }
    }
  }

  /// 卡片获焦时更新最后焦点记录；移动交接成功后虚拟位置清零。
  void _onItemFocusChanged(String id, FocusNode node) {
    if (!node.hasFocus) return;
    _lastFocusId = id;
    _lastIndex = widget.itemIds.indexOf(id);
    _virtualIndex = null;
  }

  @override
  void didUpdateWidget(TvFocusCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemIds != widget.itemIds ||
        oldWidget.columns != widget.columns) {
      // 数据或结构变化取消未完成的交接；失焦恢复在 scope 重新获焦时按需进行。
      _moveGeneration++;
      _virtualIndex = null;
    }
    final lastId = _lastFocusId;
    if (lastId != null &&
        !widget.itemIds.contains(lastId) &&
        (_nodes[lastId]?.hasFocus ?? false)) {
      // 删除持焦节点前先接住焦点，避免 Flutter 自动退回旧播放按钮等历史控件。
      // 字段/弹窗已持焦时不进入此路径；更新后仍由统一恢复逻辑选择相邻条目。
      _keyNode.requestFocus();
      if (widget.itemIds.isEmpty) {
        _exitWhenEmpty();
      } else {
        _scheduleRestoreIfFocusRevertedToAncestor();
      }
    }
  }

  @override
  void dispose() {
    _moveGeneration++;
    _restoreGeneration++;
    for (final entry in _focusListeners.entries) {
      entry.key.removeListener(entry.value);
    }
    _focusListeners.clear();
    _keyNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (widget.itemIds.isEmpty) return KeyEventResult.ignored;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null ||
        (!_focusListeners.containsKey(primary) &&
            !primary.ancestors.any(_focusListeners.containsKey))) {
      return KeyEventResult.ignored;
    }
    final current = _focusedIndex();
    if (current < 0) return KeyEventResult.ignored;
    final target = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => _moveLeft(current),
      LogicalKeyboardKey.arrowRight => _moveRight(current),
      LogicalKeyboardKey.arrowUp => _moveUp(current),
      LogicalKeyboardKey.arrowDown => _moveDown(current),
      _ => null,
    };
    if (target == null) {
      // 列表边界：交给外层默认方向遍历，焦点移向导航/工具栏/下一分区。
      return KeyEventResult.ignored;
    }
    _virtualIndex = target;
    unawaited(_transferFocus(target));
    return KeyEventResult.handled;
  }

  /// 当前按键计算的起点：优先取移动中的虚拟位置，其次最近获焦项。
  int _focusedIndex() {
    final virtual = _virtualIndex;
    if (virtual != null && virtual < widget.itemIds.length) return virtual;
    if (_lastFocusId != null) {
      final index = widget.itemIds.indexOf(_lastFocusId!);
      if (index >= 0) return index;
    }
    if (_lastIndex >= 0) {
      return _lastIndex.clamp(0, widget.itemIds.length - 1);
    }
    return -1;
  }

  int _rowOf(int index) =>
      widget.axis == Axis.horizontal ? 0 : index ~/ widget.columns;

  int _rowItemCount(int row) {
    if (widget.axis == Axis.horizontal) return widget.itemIds.length;
    final start = row * widget.columns;
    return (widget.itemIds.length - start).clamp(0, widget.columns);
  }

  int? _moveLeft(int index) {
    if (widget.axis == Axis.horizontal) {
      return index > 0 ? index - 1 : null;
    }
    return index % widget.columns > 0 ? index - 1 : null;
  }

  int? _moveRight(int index) {
    if (widget.axis == Axis.horizontal) {
      return index < widget.itemIds.length - 1 ? index + 1 : null;
    }
    final col = index % widget.columns;
    return col < _rowItemCount(_rowOf(index)) - 1 ? index + 1 : null;
  }

  int? _moveUp(int index) {
    if (widget.axis == Axis.horizontal) return null;
    final row = _rowOf(index);
    if (row == 0) return null;
    final col = index % widget.columns;
    final targetCol = col.clamp(0, _rowItemCount(row - 1) - 1);
    return (row - 1) * widget.columns + targetCol;
  }

  int? _moveDown(int index) {
    if (widget.axis == Axis.horizontal) return null;
    final row = _rowOf(index);
    if (row >= _rowCount - 1) return null;
    final col = index % widget.columns;
    // 末行可能不足整行：落到该行最接近原列的有效项目。
    final targetCol = col.clamp(0, _rowItemCount(row + 1) - 1);
    return (row + 1) * widget.columns + targetCol;
  }

  /// 把焦点交给 [index]：已挂载直接 requestFocus；未挂载先滚动再等待下一帧，
  /// 两帧后仍不可挂载则放弃本次交接并保留当前焦点。
  Future<void> _transferFocus(int index) async {
    final generation = ++_moveGeneration;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!mounted || generation != _moveGeneration) return;
      final id = widget.itemIds[index];
      final node = _nodes[id];
      if (node != null && node.canRequestFocus) {
        node.requestFocus();
        final nodeContext = node.context;
        // 跨帧交接后节点可能已随卡片卸载；只在仍挂载时滚动到可见。
        if (nodeContext != null && nodeContext.mounted) {
          unawaited(Scrollable.ensureVisible(nodeContext));
        }
        return;
      }
      await widget.revealIndex(index);
      if (!mounted || generation != _moveGeneration) return;
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// 集合失焦（弹窗打开、切分支、页面卸载或焦点卡片被刷新移除）时取消未
  /// 完成的移动，并在下一帧检查焦点是否被系统还给了外层路由 scope。
  void _handleCollectionFocusChanged(bool focused) {
    if (focused) {
      // 方向遍历落在集合自身时恢复最后焦点项，保证进入列表就有卡可操作。
      if (FocusManager.instance.primaryFocus == _keyNode) {
        _scheduleRestore();
      }
      return;
    }
    _moveGeneration++;
    _virtualIndex = null;
    _scheduleRestoreIfFocusRevertedToAncestor();
  }

  /// 焦点卡片卸载后可能暂留集合节点或回落到祖先 scope；下一帧确认归属后恢复。
  /// 已转向具体控件（复用卡片、字段或弹层）时放弃，不接管用户的新选择。
  void _scheduleRestoreIfFocusRevertedToAncestor() {
    final generation = ++_restoreGeneration;
    var attempts = 0;
    void check() {
      if (!mounted || generation != _restoreGeneration) return;
      attempts++;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null) {
        if (attempts < 3) {
          WidgetsBinding.instance.addPostFrameCallback((_) => check());
        }
        return;
      }
      if (primary == _keyNode ||
          (primary is FocusScopeNode && _keyNode.ancestors.contains(primary))) {
        _restoreLastFocus();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  /// 空列表仅回收已失去具体控件的焦点，不抢占仍在编辑的字段或弹窗。
  /// 集合节点只作为方向计算的起点，恢复到可见动作后不参与空列表遍历。
  void _exitWhenEmpty() {
    final generation = ++_restoreGeneration;
    var attempts = 0;
    void tryExit() {
      if (!mounted || generation != _restoreGeneration) return;
      attempts++;
      final primary = FocusManager.instance.primaryFocus;
      final unclaimed =
          primary == null ||
          primary == _keyNode ||
          (primary is FocusScopeNode && _keyNode.ancestors.contains(primary));
      // 已有具体节点持焦（用户抢先操作或系统分配）则不接管。
      if (!unclaimed) return;
      _keyNode.requestFocus();
      if (_keyNode.focusInDirection(TraversalDirection.up) ||
          _keyNode.focusInDirection(TraversalDirection.down)) {
        return;
      }
      if (attempts < 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) => tryExit());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryExit());
  }

  void _scheduleRestore() {
    final generation = ++_restoreGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _restoreGeneration) return;
      _restoreLastFocus();
    });
  }

  /// 按最后记录的 ID 恢复焦点；ID 已删除则取原索引夹到有效范围。
  Future<void> _restoreLastFocus() async {
    if (widget.itemIds.isEmpty) return;
    var index = -1;
    final lastId = _lastFocusId;
    if (lastId != null) index = widget.itemIds.indexOf(lastId);
    if (index < 0 && _lastIndex >= 0) {
      index = _lastIndex.clamp(0, widget.itemIds.length - 1);
    }
    if (index < 0) index = 0;
    await _transferFocus(index);
  }

  @override
  Widget build(BuildContext context) {
    return _TvFocusCollectionScope(
      state: this,
      child: Focus(
        focusNode: _keyNode,
        skipTraversal: widget.itemIds.isEmpty,
        onFocusChange: _handleCollectionFocusChanged,
        onKeyEvent: _handleKeyEvent,
        child: widget.child,
      ),
    );
  }
}
