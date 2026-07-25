import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import 'base.dart';
import 'media.dart';

class SettingsListSkeleton extends StatelessWidget {
  const SettingsListSkeleton({super.key, this.items = 4, this.showAction = false});

  final int items;
  final bool showAction;

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: Padding(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 280, height: 15),
          const SizedBox(height: LumaSpacing.xs),
          const FractionallySizedBox(
            widthFactor: 0.7,
            child: SkeletonBox(height: 15),
          ),
          if (showAction) ...[
            const SizedBox(height: LumaSpacing.lg),
            const SkeletonBox(width: 146, height: 40, radius: LumaRadii.medium),
          ],
          const SizedBox(height: LumaSpacing.lg),
          for (var index = 0; index < items; index++) ...[
            const Row(
              children: [
                SkeletonBox(width: 40, height: 40, radius: 20),
                SizedBox(width: LumaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(widthFactor: 0.46, child: SkeletonBox()),
                      SizedBox(height: LumaSpacing.xs),
                      FractionallySizedBox(
                        widthFactor: 0.72,
                        child: SkeletonBox(height: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (index + 1 < items) const SizedBox(height: LumaSpacing.lg),
          ],
        ],
      ),
    ),
  );
}

class DetailPageSkeleton extends StatelessWidget {
  const DetailPageSkeleton({
    super.key,
    this.artworkAspectRatio = 16 / 10,
  });

  final double artworkAspectRatio;

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: SingleChildScrollView(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: LumaLayout.detailMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: artworkAspectRatio,
                child: const SkeletonBox(
                  height: double.infinity,
                  radius: LumaRadii.large,
                ),
              ),
              const SizedBox(height: LumaSpacing.xl),
              const FractionallySizedBox(
                widthFactor: 0.6,
                child: SkeletonBox(height: 28),
              ),
              const SizedBox(height: LumaSpacing.md),
              const SkeletonBox(height: 15),
              const SizedBox(height: LumaSpacing.xs),
              const FractionallySizedBox(
                widthFactor: 0.78,
                child: SkeletonBox(height: 15),
              ),
              const SizedBox(height: LumaSpacing.xl),
              const SkeletonBox(height: LumaLayout.buttonHeight),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 首页加载时的分区骨架（横向卡片 + 网格）。
class HomeFeedSkeleton extends StatelessWidget {
  const HomeFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: LumaLayout.pagePaddingH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: LumaSpacing.lg),
            SkeletonBox(width: 110, height: 20),
            SizedBox(height: LumaSpacing.md),
            Row(
              children: [
                _HorizontalCardSkeleton(),
                SizedBox(width: LumaSpacing.md),
                _HorizontalCardSkeleton(),
                SizedBox(width: LumaSpacing.md),
                _HorizontalCardSkeleton(),
              ],
            ),
            SizedBox(height: LumaSpacing.xl),
            SkeletonBox(width: 90, height: 20),
            SizedBox(height: LumaSpacing.md),
            MediaGridSkeleton(items: 4, animate: false),
          ],
        ),
      ),
    );
  }
}

class _HorizontalCardSkeleton extends StatelessWidget {
  const _HorizontalCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Expanded(
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: SizedBox.expand(
          child: SkeletonBox(height: double.infinity, radius: LumaRadii.medium),
        ),
      ),
    );
  }
}

