import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../media/media_card.dart';
import '../../../core/theme.dart';
import 'base.dart';
import 'media.dart';

class SettingsListSkeleton extends StatelessWidget {
  const SettingsListSkeleton({
    super.key,
    this.items = 4,
    this.showAction = false,
  });

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
                      FractionallySizedBox(
                        widthFactor: 0.46,
                        child: SkeletonBox(),
                      ),
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
  const DetailPageSkeleton({super.key, this.artworkAspectRatio = 16 / 10});

  final double artworkAspectRatio;

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: SingleChildScrollView(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: LumaLayout.detailMaxWidth,
          ),
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

/// 首页骨架按设备呈现货架或网格，保持加载前后的内容浏览方向。
class HomeFeedSkeleton extends StatelessWidget {
  const HomeFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false) {
      return SkeletonPulse(
        child: Column(
          children: [
            for (var row = 0; row < 2; row++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: LumaSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: LumaLayout.pagePaddingH,
                      ),
                      child: SkeletonBox(width: 110, height: 28),
                    ),
                    const SizedBox(height: LumaSpacing.md),
                    SizedBox(
                      height:
                          LumaTvLayout.landscapeCardMinWidth / (16 / 9) +
                          MediaCard.textDetailsHeight(context, titleLines: 1),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: LumaLayout.pagePaddingH,
                        ),
                        itemCount: 4,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: LumaTvLayout.cardSpacing),
                        itemBuilder: (_, _) => const SizedBox(
                          width: LumaTvLayout.landscapeCardMinWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AspectRatio(
                                aspectRatio: 16 / 9,
                                child: SkeletonBox(height: double.infinity),
                              ),
                              SizedBox(height: LumaSpacing.sm),
                              SkeletonBox(width: 144, height: 18),
                              SizedBox(height: LumaSpacing.xs),
                              SkeletonBox(width: 80, height: 14),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
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
