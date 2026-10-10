// 播放器选集/清晰度选择弹层：手机用底部抽屉，宽屏与 TV 用居中对话框。
// 内容直接监听 PlayerSelectionController，加载/错误/重试/空态与选项列表
// 共用一份实现；选择成功才关闭，失败保留弹层展示错误供重选。
// 生命周期由调用方管理：打开前暂停控制层自动隐藏，返回后恢复计时。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../shared/interaction/tv_key_bindings.dart';
import '../../../shared/states/skeleton.dart';
import '../player_selection_controller.dart';

/// 选择弹层的两种内容；按钮入口共用同一份面板实现。
enum PlayerSelectionKind { episodes, qualities }

/// 打开选择面板；成功返回 true，取消返回 null，失败时保留面板供重试。
/// TV 或宽度达到导航栏断点时使用对话框，否则使用底部抽屉，与全局选择面板一致。
Future<bool?> showPlayerSelectionSheet(
  BuildContext context, {
  required PlayerSelectionController controller,
  required PlayerSelectionKind kind,
}) {
  final isTelevision =
      AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false;
  final content = PlayerSelectionPanel(
    controller: controller,
    kind: kind,
    autofocusSelected: true,
  );
  if (isTelevision ||
      MediaQuery.sizeOf(context).width >= LumaLayout.navigationRailBreakpoint) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          // 弹窗是独立路由，TV 需自行消费确认键的长按重复。
          child: isTelevision ? TvKeyBindings(child: content) : content,
        ),
      ),
    );
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => content,
  );
}

/// 选集/清晰度面板主体：监听控制器状态并处理选择提交。
/// 成功选择后自行 pop(true)；切换失败面板保留并展示内联错误。
class PlayerSelectionPanel extends StatefulWidget {
  /// 复用同一份内容呈现两类选择；提交期间禁用选项，关闭时由宿主恢复计时。
  const PlayerSelectionPanel({
    super.key,
    required this.controller,
    required this.kind,
    this.autofocusSelected = false,
  });

  final PlayerSelectionController controller;
  final PlayerSelectionKind kind;

  /// 弹层打开时聚焦当前选中项，键盘和遥控器可立即操作。
  final bool autofocusSelected;

  @override
  State<PlayerSelectionPanel> createState() => _PlayerSelectionPanelState();
}

class _PlayerSelectionPanelState extends State<PlayerSelectionPanel> {
  String? _selectionError;
  String? _pendingMediaId;
  final _selectedKey = GlobalKey();
  String? _revealedMediaId;

  void _revealSelected() {
    final id = _selectedMediaId;
    if (id == null ||
        id == _revealedMediaId ||
        !_choices.any((choice) => choice.mediaId == id)) {
      return;
    }
    _revealedMediaId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedContext = _selectedKey.currentContext;
      if (selectedContext != null) {
        Scrollable.ensureVisible(selectedContext, alignment: 0.5);
      }
    });
  }

  PlayerSelectionController get _selection => widget.controller;

  bool get _isEpisodes => widget.kind == PlayerSelectionKind.episodes;

  List<PlayerMediaChoice> get _choices =>
      _isEpisodes ? _selection.episodes : _selection.qualities;

  String? get _selectedMediaId => _isEpisodes
      ? _selection.selectedEpisodeMediaId
      : _selection.selectedQualityMediaId;

  /// 提交一次选择；成功关闭面板，失败保留面板并显示错误供重试。
  /// 控制器内部串行化选择请求，切换期间重复点击会被忽略。
  Future<void> _choose(PlayerMediaChoice choice) async {
    if (_selection.switching) return;
    setState(() {
      _selectionError = null;
      _pendingMediaId = choice.mediaId;
    });
    final accepted = _isEpisodes
        ? await _selection.selectEpisode(choice.mediaId)
        : await _selection.selectQuality(choice.mediaId);
    if (!mounted) return;
    if (accepted) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _selectionError = '切换失败，请重试';
        _pendingMediaId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _selection,
      builder: (context, _) {
        _revealSelected();
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              LumaLayout.pagePaddingH,
              LumaSpacing.lg,
              LumaLayout.pagePaddingH,
              LumaSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEpisodes ? '选集' : '清晰度',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  _isEpisodes ? '选择要播放的剧集' : '选择要播放的文件版本',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: LumaSpacing.md),
                ..._buildBody(theme),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 面板主体：加载与错误态在尚无旧选项时占位展示，已有选项时保留列表；
  /// 选择错误以行动内联提示，不会清空列表。
  Iterable<Widget> _buildBody(ThemeData theme) {
    final choices = _choices;
    final error = _selection.error ?? _selectionError;
    if (_selection.loading && choices.isEmpty) {
      return [
        for (var i = 0; i < 3; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: LumaSpacing.sm),
            child: SkeletonBox(height: 64),
          ),
      ];
    }
    final switching = _selection.switching;
    return [
      if (_selection.loading) const LinearProgressIndicator(),
      if (error != null)
        _PanelMessage(
          icon: Icons.error_outline_rounded,
          message: error,
          action: TextButton.icon(
            onPressed: _selection.loading || switching
                ? null
                : () {
                    setState(() => _selectionError = null);
                    unawaited(_selection.refresh());
                  },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ),
      if (choices.isEmpty && error == null)
        _PanelMessage(
          icon: Icons.playlist_remove_rounded,
          message: _isEpisodes ? '暂无可播放的剧集' : '暂无可切换的版本',
        ),
      for (final choice in choices)
        KeyedSubtree(
          key: choice.mediaId == _selectedMediaId ? _selectedKey : null,
          child: _PlayerSelectionTile(
            key: ValueKey('player-choice-${choice.mediaId}'),
            choice: choice,
            selected: choice.mediaId == _selectedMediaId,
            autofocus:
                widget.autofocusSelected && choice.mediaId == _selectedMediaId,
            enabled: !switching,
            switching: switching && choice.mediaId == _pendingMediaId,
            onTap: () => unawaited(_choose(choice)),
          ),
        ),
    ];
  }
}

/// 单个选项行：48dp 以上触控目标，选中项高亮并带勾选；禁用态降低透明度。
class _PlayerSelectionTile extends StatelessWidget {
  const _PlayerSelectionTile({
    super.key,
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.switching,
    required this.onTap,
    this.autofocus = false,
  });

  final PlayerMediaChoice choice;
  final bool selected;
  final bool enabled;

  /// 当前行是否正在发起切换；面板整体禁用期间该行显示进度。
  final bool switching;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: ListTile(
        autofocus: autofocus,
        enabled: enabled,
        contentPadding: EdgeInsets.zero,
        selected: selected,
        selectedColor: scheme.primary,
        leading: Icon(
          selected ? Icons.check_circle_rounded : Icons.movie_rounded,
        ),
        title: Text(choice.label),
        subtitle: choice.description == null ? null : Text(choice.description!),
        trailing: SizedBox(
          width: LumaIconSize.action,
          child: switching
              ? const Padding(
                  padding: EdgeInsets.all(LumaSpacing.xxs),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : selected
              ? Icon(Icons.check_rounded, color: scheme.primary)
              : null,
        ),
        onTap: enabled ? onTap : null,
      ),
    );
  }
}

/// 面板空态与加载失败态的占位信息。
class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LumaSpacing.lg),
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: LumaSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: LumaSpacing.md),
            action!,
          ],
        ],
      ),
    );
  }
}
