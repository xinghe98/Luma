import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';
import 'home_layout.dart';

/// 首页顶部紧凑栏：品牌标志（双击回顶）、搜索入口。
/// 只负责导航与回顶，不持有媒体状态。
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    super.key,
    required this.onOpenSearch,
    required this.onScrollToTop,
  });

  /// 打开现有搜索页面，不创建或修改搜索条件。
  final VoidCallback onOpenSearch;

  /// 双击品牌标志时回到首页顶部。
  final VoidCallback onScrollToTop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = HomeLayout.sideInset(constraints.maxWidth);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            inset,
            LumaSpacing.sm,
            inset,
            LumaSpacing.xs,
          ),
          child: _bar(scheme),
        );
      },
    );
  }

  Widget _bar(ColorScheme scheme) {
    return Row(
      children: [
        Semantics(
          button: true,
          label: '回到顶部',
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: onScrollToTop,
            child: const SizedBox(
              height: 48,
              child: Center(
                child: BrandMark(
                  variant: BrandMarkVariant.horizontal,
                  height: 28,
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '搜索',
          onPressed: onOpenSearch,
          icon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
