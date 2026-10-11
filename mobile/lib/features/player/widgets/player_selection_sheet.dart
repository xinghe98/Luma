// 播放器选集/清晰度/倍速选择弹层：手机用底部抽屉，宽屏与 TV 用居中对话框。
// 内容直接监听 PlayerSelectionController，加载/错误/重试/空态与选项列表
// 共用一份实现；选择成功才关闭，失败保留弹层展示错误供重选。
// 选集采用分段 chip + 集数网格（B 站式），清晰度/倍速用等宽 pill 网格。
// 生命周期由调用方管理：打开前暂停控制层自动隐藏，返回后恢复计时。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../shared/interaction/tv_key_bindings.dart';
import '../../../shared/states/skeleton.dart';
import '../player_controller.dart';
import '../player_selection_controller.dart';
import 'tv_player_controls.dart' show kTvPlaybackSpeeds;

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
          constraints: const BoxConstraints(maxWidth: 560),
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

/// 打开倍速选择；返回被选中的倍速，取消返回 null。
/// 与选集/清晰度共用同一套宿主判断，手机上用底部抽屉，宽屏/TV 用对话框。
Future<double?> showPlayerSpeedSheet(
  BuildContext context, {
  required PlayerController controller,
}) {
  final isTelevision =
      AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false;
  final content = _SpeedPanel(controller: controller);
  if (isTelevision ||
      MediaQuery.sizeOf(context).width >= LumaLayout.navigationRailBreakpoint) {
    return showDialog<double>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: isTelevision ? TvKeyBindings(child: content) : content,
        ),
      ),
    );
  }
  return showModalBottomSheet<double>(
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
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              LumaLayout.pagePaddingH,
              LumaSpacing.sm,
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
  List<Widget> _buildBody(ThemeData theme) {
    final choices = _choices;
    final error = _selection.error ?? _selectionError;
    if (_selection.loading && choices.isEmpty) {
      return [
        const SizedBox(height: LumaSpacing.md),
        for (var i = 0; i < 2; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: LumaSpacing.sm),
            child: SkeletonBox(height: 96),
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
      if (choices.isNotEmpty)
        _isEpisodes
            ? _EpisodeGrid(
                choices: choices,
                selectedMediaId: _selectedMediaId,
                selectedKey: _selectedKey,
                switching: switching,
                pendingMediaId: _pendingMediaId,
                autofocusSelected: widget.autofocusSelected,
                onChoose: (choice) => unawaited(_choose(choice)),
              )
            : _QualityGrid(
                choices: choices,
                selectedMediaId: _selectedMediaId,
                selectedKey: _selectedKey,
                switching: switching,
                pendingMediaId: _pendingMediaId,
                autofocusSelected: widget.autofocusSelected,
                onChoose: (choice) => unawaited(_choose(choice)),
              ),
    ];
  }
}

/// 选集网格：顶部为分段 chip（每 50 集一段，多季按季划分），
/// 下面是等宽集数格子，当前集高亮描边并标注「正在播放」。
class _EpisodeGrid extends StatefulWidget {
  const _EpisodeGrid({
    required this.choices,
    required this.selectedMediaId,
    required this.selectedKey,
    required this.switching,
    required this.pendingMediaId,
    required this.autofocusSelected,
    required this.onChoose,
  });

  final List<PlayerMediaChoice> choices;
  final String? selectedMediaId;
  final GlobalKey selectedKey;
  final bool switching;
  final String? pendingMediaId;
  final bool autofocusSelected;
  final ValueChanged<PlayerMediaChoice> onChoose;

  @override
  State<_EpisodeGrid> createState() => _EpisodeGridState();
}

class _EpisodeGridState extends State<_EpisodeGrid> {
  /// 当前展开的分段在 [_segments] 里的下标；首次定位到选中集所在段。
  int _segment = 0;
  bool _initialized = false;

  /// 把选项按季或每 50 集切成段；段标题供 chip 行显示。
  List<_EpisodeSegment> get _segments {
    final choices = widget.choices;
    // 没有结构化季集信息时退化为单段，保持网格可用。
    final hasNumbers = choices.any((c) => c.episode != null);
    if (!hasNumbers) {
      return [_EpisodeSegment(label: '全部', choices: choices)];
    }
    final segments = <_EpisodeSegment>[];
    var index = 0;
    while (index < choices.length) {
      final start = index;
      final season = choices[index].season;
      // 同季最多 50 集为一段；季变化或超过 50 集时另起一段。
      final seasonChoices = <PlayerMediaChoice>[];
      while (index < choices.length &&
          choices[index].season == season &&
          seasonChoices.length < 50) {
        seasonChoices.add(choices[index]);
        index++;
      }
      final first = seasonChoices.first.episode;
      final last = seasonChoices.last.episode;
      final label = season == null
          ? (first == last ? '$first' : '$first-$last')
          : season == 0
          ? (first == last ? '特别篇' : '特别篇 $first-$last')
          : (first == last ? '第 $season 季' : '第 $season 季 $first-$last');
      segments.add(
        _EpisodeSegment(label: label, choices: List.unmodifiable(seasonChoices)),
      );
      assert(index > start, '分段必须前进');
    }
    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final segments = _segments;
    if (!_initialized) {
      _initialized = true;
      final selected = widget.selectedMediaId;
      if (selected != null) {
        for (var i = 0; i < segments.length; i++) {
          if (segments[i].choices.any((c) => c.mediaId == selected)) {
            _segment = i;
            break;
          }
        }
      }
    }
    final segment = segments[_segment.clamp(0, segments.length - 1)];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (segments.length > 1)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: segments.length,
              separatorBuilder: (_, _) => const SizedBox(width: LumaSpacing.xs),
              itemBuilder: (context, index) {
                final item = segments[index];
                final selected = index == _segment;
                return ChoiceChip(
                  label: Text(item.label),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: widget.switching
                      ? null
                      : (_) => setState(() => _segment = index),
                  labelStyle: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
        if (segments.length > 1) const SizedBox(height: LumaSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            // 每格最小 96dp，等比填满；与 B 站选集网格一致的 4-6 列。
            final columns = (constraints.maxWidth / 96)
                .floor()
                .clamp(3, 6);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              addAutomaticKeepAlives: false,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: LumaSpacing.xs,
                crossAxisSpacing: LumaSpacing.xs,
                // 固定行高容纳集号 + 副标题 + 进度条，随文字缩放增加。
                mainAxisExtent:
                    52 * MediaQuery.textScalerOf(context).scale(1) + 8,
              ),
              itemCount: segment.choices.length,
              itemBuilder: (context, index) {
                final choice = segment.choices[index];
                final selected = choice.mediaId == widget.selectedMediaId;
                return KeyedSubtree(
                  key: selected ? widget.selectedKey : null,
                  child: _EpisodeCell(
                    key: ValueKey('player-choice-${choice.mediaId}'),
                    choice: choice,
                    selected: selected,
                    autofocus:
                        widget.autofocusSelected &&
                        choice.mediaId == widget.selectedMediaId,
                    enabled: !widget.switching,
                    switching:
                        widget.switching &&
                        choice.mediaId == widget.pendingMediaId,
                    onTap: () => widget.onChoose(choice),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

@immutable
class _EpisodeSegment {
  const _EpisodeSegment({required this.label, required this.choices});
  final String label;
  final List<PlayerMediaChoice> choices;
}

/// 单个集数格：主标题为集号，副标题为集名；选中时描边 + 「正在播放」标记，
/// 底部进度条复用服务端续播进度，看完的集显示对勾。
class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
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
  final bool switching;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(LumaRadii.medium);
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final progress = choice.progressMs != null &&
            choice.durationMs != null &&
            choice.durationMs! > 0
        ? (choice.progressMs! / choice.durationMs!).clamp(0.0, 1.0)
        : 0.0;
    final title = choice.episode != null ? '${choice.episode}' : choice.label;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: choice.description ?? choice.label,
      child: Material(
        color: background,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: autofocus,
          onTap: enabled ? onTap : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: selected
                  ? Border.all(color: scheme.primary, width: LumaStroke.focused)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: LumaSpacing.sm,
              vertical: LumaSpacing.xxs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                    if (switching)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (selected)
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 18,
                        color: scheme.onPrimaryContainer,
                      )
                    else if (choice.completed)
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
                if (selected || choice.title != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    selected ? '正在播放' : (choice.title ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (progress > 0 && !choice.completed) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: scheme.surfaceContainerHigh,
                      valueColor: AlwaysStoppedAnimation(
                        selected ? scheme.onPrimaryContainer : scheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 清晰度网格：等宽 pill，当前项描边 + 对勾，描述行展示版本/编码信息。
class _QualityGrid extends StatelessWidget {
  const _QualityGrid({
    required this.choices,
    required this.selectedMediaId,
    required this.selectedKey,
    required this.switching,
    required this.pendingMediaId,
    required this.autofocusSelected,
    required this.onChoose,
  });

  final List<PlayerMediaChoice> choices;
  final String? selectedMediaId;
  final GlobalKey selectedKey;
  final bool switching;
  final String? pendingMediaId;
  final bool autofocusSelected;
  final ValueChanged<PlayerMediaChoice> onChoose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 128).floor().clamp(2, 4);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          addAutomaticKeepAlives: false,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: LumaSpacing.xs,
            crossAxisSpacing: LumaSpacing.xs,
            childAspectRatio: 2.6,
          ),
          itemCount: choices.length,
          itemBuilder: (context, index) {
            final choice = choices[index];
            final selected = choice.mediaId == selectedMediaId;
            return KeyedSubtree(
              key: selected ? selectedKey : null,
              child: _ChoicePill(
                key: ValueKey('player-choice-${choice.mediaId}'),
                label: choice.label,
                description: choice.description,
                selected: selected,
                autofocus: autofocusSelected && selected,
                enabled: !switching,
                switching: switching && choice.mediaId == pendingMediaId,
                onTap: () => onChoose(choice),
              ),
            );
          },
        );
      },
    );
  }
}

/// 等宽选择 pill：清晰度/倍速共用；选中描边、禁用降透明、切换中行内转圈。
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    super.key,
    required this.label,
    this.description,
    required this.selected,
    required this.enabled,
    required this.switching,
    required this.onTap,
    this.autofocus = false,
  });

  final String label;
  final String? description;
  final bool selected;
  final bool enabled;
  final bool switching;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(LumaRadii.medium);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          autofocus: autofocus,
          onTap: enabled ? onTap : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: selected
                  ? Border.all(color: scheme.primary, width: LumaStroke.focused)
                  : null,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: LumaSpacing.sm,
              vertical: LumaSpacing.xs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                    if (switching) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ] else if (selected) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: scheme.onPrimaryContainer,
                      ),
                    ],
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 倍速面板：固定档位的等宽 pill 网格，当前倍速高亮描边。
class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.speed;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              LumaLayout.pagePaddingH,
              LumaSpacing.sm,
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
                      child: Text('倍速', style: theme.textTheme.titleLarge),
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
                const SizedBox(height: LumaSpacing.sm),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = (constraints.maxWidth / 96)
                        .floor()
                        .clamp(3, 5);
                    return GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: columns,
                      mainAxisSpacing: LumaSpacing.xs,
                      crossAxisSpacing: LumaSpacing.xs,
                      childAspectRatio: 2.6,
                      children: [
                        for (final speed in kTvPlaybackSpeeds)
                          _ChoicePill(
                            key: ValueKey('player-speed-$speed'),
                            label: speed == 1 ? '1.0×' : '$speed×',
                            selected: (speed - current).abs() < 0.001,
                            enabled: true,
                            switching: false,
                            onTap: () =>
                                Navigator.of(context).pop(speed),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
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
