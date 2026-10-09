import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../app/app_metadata.g.dart';

enum BrandMarkVariant { symbol, horizontal }

/// 根据主题选择品牌资源，并按统一占位尺寸布局 symbol 与横版 Logo。
///
/// 浅色主题用石墨画框 + 加深晨光的 color 版，深色主题用画框白 + 晨光的 dark 版。
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

  /// 返回指定变体在给定亮度下的资源路径；开屏预缓存与渲染共用这一结果。
  static String assetFor({
    required BrandMarkVariant variant,
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    return switch (variant) {
      BrandMarkVariant.symbol =>
        isDark
            ? 'assets/luma-symbol-dark-transparent.png'
            : 'assets/luma-symbol-color-transparent.png',
      BrandMarkVariant.horizontal =>
        isDark
            ? 'assets/luma-logo-horizontal-dark-transparent.png'
            : 'assets/luma-logo-horizontal-color-transparent.png',
    };
  }

  /// 横版资源画布为 1448×1086，lockup 居中放在此裁切框内；
  /// 裁切框沿用旧版占位尺寸，保证各页面横版 Logo 的布局宽高不变。
  static const _horizontalSourceSize = Size(1448, 1086);
  static const _horizontalCropRect = Rect.fromLTWH(129, 302, 1205, 407);

  /// 构建裁去资源外围透明留白后的品牌标志，不改变原始图片内容。
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
      return _CroppedBrandAsset(
        asset: asset,
        sourceSize: _horizontalSourceSize,
        cropRect: _horizontalCropRect,
        height: resolvedHeight,
      );
    }

    return Image.asset(
      asset,
      width: resolvedHeight,
      height: resolvedHeight,
      fit: BoxFit.contain,
      filterQuality: _filterQuality,
    );
  }
}

/// 品牌资源源图远大于显示尺寸（symbol 约缩到 0.03–0.08 倍）。`high` 走三次插值、
/// 不用 mipmap，大幅缩小时边缘会出锯齿；`medium` 走 mipmap 线性采样，边缘平滑。
const _filterQuality = FilterQuality.medium;

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
                filterQuality: _filterQuality,
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
        Text(AppMetadata.displayName, style: theme.textTheme.headlineSmall),
        const SizedBox(width: LumaSpacing.xs),
        Text(
          AppMetadata.companyName,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
