// TV 连接页按观看距离分开品牌说明与登录操作，复用 ConnectionForm 的字段和业务回调。
// 布局不持有连接状态；宽屏分栏，窄屏和大字体按内容顺序滚动。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';

class TvConnectionLayout extends StatelessWidget {
  const TvConnectionLayout({super.key, required this.form, this.proxyAction});

  final Widget form;
  final Widget? proxyAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 800 &&
            MediaQuery.textScalerOf(context).scale(18) <= 25;
        final introduction = Column(
          key: const ValueKey('tv-connection-introduction'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BrandMark(variant: BrandMarkVariant.horizontal, height: 48),
            const SizedBox(height: LumaSpacing.xl),
            Text(
              '你的影库，\n在大屏相见',
              style: theme.textTheme.headlineLarge?.copyWith(
                fontSize: 36,
                height: 1.2,
              ),
            ),
            const SizedBox(height: LumaSpacing.lg),
            Text(
              '连接轻影服务器',
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 24),
            ),
            const SizedBox(height: LumaSpacing.sm),
            Text(
              '输入服务器的局域网地址和账号。连接后，即可浏览和播放你的影库。',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: LumaSpacing.lg),
            Text(
              '方向键选择 · 确认键输入 · 返回键结束编辑',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
        final fields = ConstrainedBox(
          key: const ValueKey('tv-connection-fields'),
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '服务器登录',
                      style: theme.textTheme.titleLarge?.copyWith(fontSize: 24),
                    ),
                  ),
                  ?proxyAction,
                ],
              ),
              const SizedBox(height: LumaSpacing.lg),
              form,
            ],
          ),
        );
        return SingleChildScrollView(
          key: const PageStorageKey('tv-connection-scroll'),
          padding: const EdgeInsets.all(LumaSpacing.lg),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: introduction),
                    const SizedBox(width: LumaSpacing.xxl),
                    Expanded(
                      flex: 6,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: fields,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    introduction,
                    const SizedBox(height: LumaSpacing.xl),
                    Align(alignment: Alignment.centerLeft, child: fields),
                  ],
                ),
        );
      },
    );
  }
}
