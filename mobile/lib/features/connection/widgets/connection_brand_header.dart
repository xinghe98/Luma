// 连接页品牌头部，负责展示标志、标题与说明，不读取或修改连接状态。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../shared/branding/brand_mark.dart';

/// 展示连接流程的品牌入口，不处理表单、焦点或网络请求。
class ConnectionBrandHeader extends StatelessWidget {
  const ConnectionBrandHeader({super.key});

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LumaSpacing.lg,
          LumaSpacing.xl,
          LumaSpacing.lg,
          LumaSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Theme(
              data: theme,
              child: const BrandMark(
                variant: BrandMarkVariant.horizontal,
                height: 56,
              ),
            ),
            const SizedBox(height: LumaSpacing.xl),
            Text(
              '连接你的轻影服务器',
              textAlign: TextAlign.left,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: luma.onBrandSurface,
              ),
            ),
            const SizedBox(height: LumaSpacing.xs),
            Text(
              '在可信的家庭网络中，连接并浏览自己的影像。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: luma.onBrandSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
