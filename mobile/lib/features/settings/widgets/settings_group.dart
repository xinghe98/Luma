// 设置分组容器：标题下方一张 SurfaceCard 装多行设置项，行间用分隔线连接。
// 自身无状态，分组顺序由页面决定。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/layout/surface_card.dart';

/// 卡片内分隔线的起始缩进，对齐 ListTile 标题起点。
const double _leadingInset = 56;

/// 一组设置项的标题加卡片容器，相邻项之间自动插入分隔线。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LumaSpacing.md,
            LumaSpacing.lg,
            LumaSpacing.md,
            LumaSpacing.xs,
          ),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: _leadingInset),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
