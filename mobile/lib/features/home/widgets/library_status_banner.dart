// 首页媒体库状态横幅：仅在扫描中或扫描异常时出现，
// 跳转设置在「查看」按钮上，整卡不响应点击。
import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_scope.dart';
import '../../../core/theme.dart';
import '../../../shared/layout/surface_card.dart';
import '../../shell/app_destination.dart';

/// 显示扫描进度或异常的紧凑横幅；无状态时返回空占位，不占布局。
class LibraryStatusBanner extends StatelessWidget {
  const LibraryStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        if (!settings.isScanning && !settings.hasScanProblem) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final scanning = settings.isScanning;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            LumaLayout.pageHorizontalPadding(MediaQuery.sizeOf(context).width),
            LumaSpacing.sm,
            LumaLayout.pageHorizontalPadding(MediaQuery.sizeOf(context).width),
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LumaLayout.contentMaxWidth,
              ),
              child: SurfaceCard(
                color: scheme.surfaceContainerHigh,
                padding: const EdgeInsets.symmetric(
                  horizontal: LumaSpacing.md,
                  vertical: LumaSpacing.sm,
                ),
                child: Row(
                  children: [
                    if (scanning)
                      SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: (settings.scanProgress ?? 0) > 0
                              ? settings.scanProgress
                              : null,
                          color: scheme.primary,
                        ),
                      )
                    else
                      Icon(
                        Icons.error_outline_rounded,
                        color: context.luma.warning,
                        size: 20,
                      ),
                    const SizedBox(width: LumaSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.scanStatusLabel,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: LumaSpacing.xxs),
                          Text(
                            settings.scanStatusDetails,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: LumaSpacing.sm),
                    TextButton(
                      onPressed: () =>
                          context.goToDestination(AppDestination.settings),
                      child: const Text('查看'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
