import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';
import 'scan_status_card.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.onOpenSearch,
    required this.onScrollToTop,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onScrollToTop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LumaLayout.contentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            LumaLayout.pagePaddingH,
            LumaSpacing.lg,
            LumaLayout.pagePaddingH,
            LumaSpacing.sm,
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
                      child: const Align(
                        alignment: Alignment.centerLeft,
                        child: BrandMark(
                          variant: BrandMarkVariant.symbol,
                          height: 40,
                        ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '搜索媒体',
                    onPressed: onOpenSearch,
                    icon: const Icon(Icons.search_rounded),
                  ),
                ],
              ),
              const SizedBox(height: LumaSpacing.xl),
              Text(
                '${greetingForHour(DateTime.now().hour)}，欢迎回来',
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: LumaSpacing.xs),
              Text(
                '在熟悉的影像里，继续今天的片刻。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: LumaSpacing.lg),
              const ScanStatusCard(),
            ],
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
