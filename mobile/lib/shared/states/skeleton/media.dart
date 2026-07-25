import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import 'base.dart';

class MediaGridSkeleton extends StatelessWidget {
  const MediaGridSkeleton({super.key, this.items = 6, this.animate = true});

  final int items;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: LumaLayout.gridColumns(width),
            mainAxisSpacing: LumaSpacing.lg,
            crossAxisSpacing: LumaSpacing.md,
            childAspectRatio: LumaLayout.mediaCardAspectRatio(width),
          ),
          itemCount: items,
          itemBuilder: (context, index) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: SizedBox.expand(
                  child: SkeletonBox(
                    height: double.infinity,
                    radius: LumaRadii.medium,
                  ),
                ),
              ),
              SizedBox(height: LumaSpacing.xs),
              FractionallySizedBox(widthFactor: 0.72, child: SkeletonBox()),
              SizedBox(height: LumaSpacing.xs),
              FractionallySizedBox(
                widthFactor: 0.45,
                child: SkeletonBox(height: 11),
              ),
            ],
          ),
        );
      },
    );
    return animate ? SkeletonPulse(child: grid) : grid;
  }
}

/// 与影视库 2:3 海报墙相同密度的加载骨架。
class PosterGridSkeleton extends StatelessWidget {
  const PosterGridSkeleton({super.key, this.items = 10});

  final int items;

  @override
  Widget build(BuildContext context) => SkeletonPulse(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width < 360
            ? 2
            : width < 620
            ? 3
            : width < 900
            ? 5
            : width < 1240
            ? 6
            : 8;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: LumaSpacing.md,
            mainAxisSpacing: LumaSpacing.lg,
            childAspectRatio: 0.59,
          ),
          itemBuilder: (_, _) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox.expand(
                  child: SkeletonBox(
                    height: double.infinity,
                    radius: LumaRadii.large,
                  ),
                ),
              ),
              SizedBox(height: LumaSpacing.xs),
              FractionallySizedBox(widthFactor: 0.82, child: SkeletonBox()),
              SizedBox(height: LumaSpacing.xs),
              FractionallySizedBox(
                widthFactor: 0.52,
                child: SkeletonBox(height: 11),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// 设置类页面的首屏骨架，保留说明、操作区和列表的空间关系。
