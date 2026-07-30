import 'package:flutter/material.dart';

import '../../core/theme.dart';

enum BrandMarkVariant { symbol, horizontal }

/// 根据主题选择品牌资源，并按可见图形尺寸统一 symbol 与横版 Logo 的布局。
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

  /// 构建去除资源透明留白后的品牌标志，不改变原始图片内容。
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
      final cropRect = brightness == Brightness.dark
          ? const Rect.fromLTWH(122, 314, 1208, 409)
          : const Rect.fromLTWH(129, 302, 1205, 407);
      return _CroppedBrandAsset(
        asset: asset,
        sourceSize: const Size(1448, 1086),
        cropRect: cropRect,
        height: resolvedHeight,
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

class _CroppedBrandAsset extends StatelessWidget {
  const _CroppedBrandAsset({
    required this.asset,
    required this.sourceSize,
    required this.cropRect,
    required this.height,
  });

  final String asset;
  final Size sourceSize;
  final Rect cropRect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scale = height / cropRect.height;
    return SizedBox(
      width: cropRect.width * scale,
      height: height,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: -cropRect.left * scale,
              top: -cropRect.top * scale,
              width: sourceSize.width * scale,
              height: sourceSize.height * scale,
              child: Image.asset(
                asset,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
            ),
          ],
        ),
      ),
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
