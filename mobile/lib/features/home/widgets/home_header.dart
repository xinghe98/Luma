import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';
import 'scan_status_card.dart';

/// 展示首页品牌信息、搜索入口和扫描状态，不改变媒体加载流程。
class HomeHeader extends StatelessWidget {
  const HomeHeader({
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
    final theme = Theme.of(context);
    final luma = context.luma;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: luma.brandSurfaceVariant,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(LumaRadii.extraLarge),
        ),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: LumaLayout.contentMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LumaLayout.pagePaddingH,
              LumaSpacing.md,
              LumaLayout.pagePaddingH,
              LumaSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: onScrollToTop,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Theme(
                            data: theme,
                            child: const BrandMark(
                              variant: BrandMarkVariant.symbol,
                              height: 44,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LumaSpacing.lg),
                Text(
                  '${greetingForHour(DateTime.now().hour)}，欢迎回来',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: luma.onBrandSurface,
                  ),
                ),
                const SizedBox(height: LumaSpacing.xs),
                Text(
                  '在熟悉的影像里，继续今天的片刻。',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: luma.onBrandSurfaceMuted,
                  ),
                ),
                const SizedBox(height: LumaSpacing.lg),
                _HomeSearchButton(onPressed: onOpenSearch),
                const SizedBox(height: LumaSpacing.sm),
                const ScanStatusCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSearchButton extends StatelessWidget {
  const _HomeSearchButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(LumaRadii.medium);
    return Semantics(
      button: true,
      label: '搜索媒体',
      child: Material(
        color: colors.surfaceContainer,
        elevation: 1,
        shadowColor: colors.shadow.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.52),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: SizedBox(
            height: LumaLayout.buttonHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: LumaSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: colors.primary,
                    size: LumaIconSize.action,
                  ),
                  const SizedBox(width: LumaSpacing.sm),
                  Text(
                    '搜索你的媒体',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.tune_rounded,
                    color: colors.onSurfaceVariant,
                    size: LumaIconSize.inline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 按设备本地时间提供自然问候，方便测试且不依赖服务端时区。
String greetingForHour(int hour) {
  if (hour >= 5 && hour < 12) return '早上好';
  if (hour >= 12 && hour < 18) return '下午好';
  return '晚上好';
}
