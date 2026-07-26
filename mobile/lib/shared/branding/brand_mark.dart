import 'package:flutter/material.dart';

import '../../core/theme.dart';

enum BrandMarkVariant { symbol, horizontal }

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.compact = false,
    this.variant = BrandMarkVariant.symbol,
    this.height,
  });

  final bool compact;
  final BrandMarkVariant variant;
  final double? height;

  static String assetFor({
    required BrandMarkVariant variant,
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    return switch (variant) {
      BrandMarkVariant.symbol =>
        isDark
            ? 'assets/luma-symbol-white-transparent.png'
            : 'assets/luma-symbol-color-transparent.png',
      BrandMarkVariant.horizontal =>
        isDark
            ? 'assets/luma-logo-horizontal-white-transparent.png'
            : 'assets/luma-logo-horizontal-color-transparent.png',
    };
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final asset = assetFor(variant: variant, brightness: brightness);
    final resolvedHeight =
        height ??
        switch (variant) {
          BrandMarkVariant.symbol => compact ? 34.0 : 48.0,
          BrandMarkVariant.horizontal => compact ? 28.0 : 36.0,
        };

    if (variant == BrandMarkVariant.horizontal) {
      return Image.asset(
        asset,
        height: resolvedHeight,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }

    return Image.asset(
      asset,
      width: resolvedHeight,
      height: resolvedHeight,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

/// 带中文名的品牌行，用于连接页等需要强调产品名的位置。
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.showWordmark = true});

  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    if (showWordmark) {
      return const BrandMark(variant: BrandMarkVariant.horizontal, height: 36);
    }

    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(variant: BrandMarkVariant.symbol, height: 44),
        const SizedBox(width: LumaSpacing.sm),
        Text('轻影', style: theme.textTheme.headlineSmall),
        const SizedBox(width: LumaSpacing.xs),
        Text(
          'Luma',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
