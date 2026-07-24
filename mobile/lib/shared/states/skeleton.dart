import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 脉动的占位块，用于加载态骨架屏。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = LumaRadii.small,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 一整组骨架只使用一个 ticker；系统减少动态效果时保持静态。
class _SkeletonPulse extends StatefulWidget {
  const _SkeletonPulse({required this.child});

  final Widget child;

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(
      begin: 0.45,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

/// 与 [ResponsiveMediaGrid] 同布局的网格骨架。
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
    return animate ? _SkeletonPulse(child: grid) : grid;
  }
}

/// 与影视库 2:3 海报墙相同密度的加载骨架。
class PosterGridSkeleton extends StatelessWidget {
  const PosterGridSkeleton({super.key, this.items = 10});

  final int items;

  @override
  Widget build(BuildContext context) => _SkeletonPulse(
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
class SettingsListSkeleton extends StatelessWidget {
  const SettingsListSkeleton({super.key, this.items = 4, this.showAction = false});

  final int items;
  final bool showAction;

  @override
  Widget build(BuildContext context) => _SkeletonPulse(
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

/// Layout-stable media detail placeholder for routes without initial content.
class DetailPageSkeleton extends StatelessWidget {
  const DetailPageSkeleton({
    super.key,
    this.artworkAspectRatio = 16 / 10,
  });

  final double artworkAspectRatio;

  @override
  Widget build(BuildContext context) => _SkeletonPulse(
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
    return const _SkeletonPulse(
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
