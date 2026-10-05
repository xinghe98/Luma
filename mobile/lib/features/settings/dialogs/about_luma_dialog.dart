import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../app/app_metadata.g.dart';
import '../../../shared/branding/brand_mark.dart';
import '../../../shared/interaction/tv_key_bindings.dart';
import '../../details/widgets/tv_scrollable_detail_region.dart';

/// 显示应用说明；关闭弹窗不会修改任何设置。
void showAboutLumaDialog(BuildContext context) {
  final isTelevision =
      AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false;
  showDialog<void>(
    context: context,
    animationStyle: AnimationStyle.noAnimation,
    builder: (_) => _AboutLumaDialog(isTelevision: isTelevision),
  );
}

class _AboutLumaDialog extends StatefulWidget {
  const _AboutLumaDialog({required this.isTelevision});

  final bool isTelevision;

  @override
  State<_AboutLumaDialog> createState() => _AboutLumaDialogState();
}

class _AboutLumaDialogState extends State<_AboutLumaDialog> {
  /// TV：「开源许可」触发按钮的焦点节点；许可页关闭后把焦点交回这里。
  final FocusNode _licenseButtonFocus = FocusNode(
    debugLabel: 'about-license-button',
  );

  @override
  void dispose() {
    _licenseButtonFocus.dispose();
    super.dispose();
  }

  /// TV：推入独立的许可页（长文与包列表方向键可滚动），关闭后焦点回到
  /// 「开源许可」按钮；普通端保留系统 showLicensePage。
  Future<void> _openLicense() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const _TvLicenseView(),
      ),
    );
    if (mounted && _licenseButtonFocus.context != null) {
      _licenseButtonFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${AppMetadata.displayName}是一款连接家庭服务器的私有影像管理播放器。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          '媒体数据由已连接的${AppMetadata.displayName}服务器提供。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          '版本 ${AppMetadata.version} · ${AppMetadata.companyName}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (AppMetadata.authorName.isNotEmpty) ...[
          const SizedBox(height: LumaSpacing.sm),
          Text(
            '作者：${AppMetadata.authorName}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: LumaSpacing.sm),
        Text(
          '界面字体采用 MiSans，版权归小米科技有限责任公司所有。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: LumaSpacing.sm),
        Text(
          'Xray-core v26.7.28 源码：'
          'https://github.com/XTLS/Xray-core/tree/v26.7.28',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return AlertDialog(
      scrollable: true,
      title: const BrandMark(variant: BrandMarkVariant.horizontal, height: 32),
      // TV：说明文字放可聚焦滚动区域，方向键可滚动到边界后移出。
      content: widget.isTelevision
          ? TvScrollableDetailRegion(child: content)
          : content,
      actions: [
        TextButton(
          focusNode: widget.isTelevision ? _licenseButtonFocus : null,
          onPressed: () {
            if (widget.isTelevision) {
              unawaited(_openLicense());
            } else {
              showLicensePage(
                context: context,
                applicationName: AppMetadata.displayName,
                applicationVersion: AppMetadata.version,
                applicationLegalese: 'libXray v26.7.28 · Xray-core v26.7.28',
              );
            }
          },
          child: const Text('开源许可'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

/// 许可页的一行：包名标题或带缩进的许可段落。
class _LicenseRow {
  const _LicenseRow.header(this.text) : indent = null;

  const _LicenseRow.paragraph(this.text, this.indent);

  final String text;

  /// 段落缩进层级；null 表示包名标题行。
  final int? indent;
}

/// TV 开源许可页：内容全部来自 [LicenseRegistry] 的真实注册许可，不复制
/// 静态文案。包列表与许可长文在同一个可聚焦滚动区域内，方向键按视口滚动；
/// 系统 Back 或「关闭」按钮退出，焦点由打开方交回触发按钮。
class _TvLicenseView extends StatefulWidget {
  const _TvLicenseView();

  @override
  State<_TvLicenseView> createState() => _TvLicenseViewState();
}

class _TvLicenseViewState extends State<_TvLicenseView> {
  final _scroll = ScrollController();
  Future<List<_LicenseRow>>? _rows;

  @override
  void initState() {
    super.initState();
    _rows = _loadRows();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 收集全部注册许可并摊平为行；解析可能较慢，交由页面异步等待。
  Future<List<_LicenseRow>> _loadRows() async {
    final rows = <_LicenseRow>[];
    try {
      await for (final entry in LicenseRegistry.licenses) {
        for (final package in entry.packages) {
          rows.add(_LicenseRow.header(package));
        }
        for (final paragraph in entry.paragraphs) {
          rows.add(_LicenseRow.paragraph(paragraph.text, paragraph.indent));
        }
      }
    } catch (_) {
      // 许可资源加载失败（如缺少 NOTICES 资源的环境）时退化为空列表展示。
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 居中限宽：客厅电视上避免长文一行过宽难以阅读。
    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LumaLayout.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(LumaSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text('开源许可', style: theme.textTheme.headlineSmall),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _TvLicenseScrollRegion(
                controller: _scroll,
                child: FutureBuilder<List<_LicenseRow>>(
                  future: _rows,
                  builder: (context, snapshot) {
                    final rows = snapshot.data;
                    if (rows == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (rows.isEmpty) {
                      return const Center(child: Text('暂无可显示的开源许可内容。'));
                    }
                    return ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(LumaSpacing.lg),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final indent = row.indent;
                        if (indent == null) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              top: LumaSpacing.md,
                              bottom: LumaSpacing.xs,
                            ),
                            child: Text(
                              row.text,
                              style: theme.textTheme.titleSmall,
                            ),
                          );
                        }
                        final centered =
                            indent == LicenseParagraph.centeredIndent;
                        return Padding(
                          padding: EdgeInsets.only(
                            top: LumaSpacing.xs,
                            left: centered ? 0 : LumaSpacing.sm * indent,
                          ),
                          child: Text(
                            row.text,
                            textAlign: centered
                                ? TextAlign.center
                                : TextAlign.start,
                            style: theme.textTheme.bodyMedium,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // 本路由在壳层之外推入，需自带确认键映射；返回关闭由路由自身处理。
    return Scaffold(
      body: SafeArea(child: TvKeyBindings(child: body)),
    );
  }
}

/// 许可页滚动焦点区：整个许可内容（包列表+长文）共享一个焦点，方向键按
/// 视口 80% 滚动；到边界后交还默认方向遍历，把焦点移到头部「关闭」按钮。
/// 与共享 TvScrollableDetailRegion 的差异仅在滚动目标：本区域持控制器，
/// 可包裹懒构建的 ListView.builder，避免许可长文一次性全部构建。
class _TvLicenseScrollRegion extends StatefulWidget {
  const _TvLicenseScrollRegion({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  State<_TvLicenseScrollRegion> createState() => _TvLicenseScrollRegionState();
}

class _TvLicenseScrollRegionState extends State<_TvLicenseScrollRegion> {
  final _focus = FocusNode(debugLabel: 'tv-license-scroll-region');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowUp &&
        key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    if (!widget.controller.hasClients) return KeyEventResult.ignored;
    final position = widget.controller.position;
    final delta = position.viewportDimension * 0.8;
    final target =
        (position.pixels +
                (key == LogicalKeyboardKey.arrowDown ? delta : -delta))
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    // 已到边界：交给默认方向遍历，把焦点移出本区域。
    if ((target - position.pixels).abs() < 0.5) {
      return KeyEventResult.ignored;
    }
    widget.controller.jumpTo(target);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}
