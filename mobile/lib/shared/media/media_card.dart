import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import '../formatters/date_formatter.dart';
import '../formatters/duration_formatter.dart';
import '../interaction/luma_focusable_surface.dart';
import 'cover_progress_bar.dart';
import 'luma_favorite_button.dart';
import 'media_artwork.dart';
import 'media_badge.dart';
import 'media_selection_marker.dart';

/// 视频和图片网格共用的信息卡片，封面、标题与元信息保持稳定的交互轮廓内距。
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onFavorite,
    this.compact = false,
    this.heroTag,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.focusId,
    this.focusBorderWidth = 2,
    this.artworkFit,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final bool compact;
  final String? heroTag;

  /// TV 列表焦点参数，经 TV 网格/货架转发给 LumaFocusableSurface。
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  /// TV 集合内的稳定身份；普通端为空不参与集合注册。
  final String? focusId;

  /// 聚焦描边宽度；TV 传 LumaTvLayout.focusStroke。
  final double focusBorderWidth;

  /// 封面适配方式；为空保持默认 cover，TV 图片网格传 contain 统一画框。
  final BoxFit? artworkFit;

  /// 图片库批量选择态：封面左上角渲染勾选标记；默认关闭不影响既有调用。
  final bool selectionMode;

  /// 当前项是否已选中；仅在 [selectionMode] 为 true 时生效。
  final bool selected;

  /// 长按回调（如选择态下进入详情）；普通端封面长按转发给 InkWell。
  final VoidCallback? onLongPress;

  /// 按实际字体与文字缩放测量行高；容器每次构建测量一次，供全部卡片复用。
  static double textDetailsHeight(
    BuildContext context, {
    int titleLines = 2,
    TextStyle? titleStyle,
    TextStyle? subtitleStyle,
  }) {
    final theme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final title = titleStyle ?? theme.titleSmall!;
    final subtitle = subtitleStyle ?? theme.bodySmall!;
    final painter = TextPainter(
      text: TextSpan(text: '国Ag', style: title),
      textScaler: scaler,
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final titleHeight = painter.height.ceilToDouble();
    painter.text = TextSpan(text: '国Ag', style: subtitle);
    painter.layout();
    final subtitleHeight = painter.height.ceilToDouble();
    painter.dispose();
    return titleHeight * titleLines +
        subtitleHeight +
        LumaSpacing.xs +
        LumaSpacing.xxs;
  }

  /// 网格与货架按封面比例、文字区和视频内距计算行高；图片卡片沿用同一行高。
  static double heightForWidth(double width, {required double detailsHeight}) {
    const insets = LumaSpacing.xs * 2;
    return (width - insets) / (16 / 10) + detailsHeight + insets;
  }

  /// TV 封面使用无内嵌边框的横版画幅；普通端保留既有卡片比例和内距。
  @override
  Widget build(BuildContext context) {
    final duration = formatDuration(item.duration);
    final television =
        AppScope.maybeOf(context)?.deviceProfile.isTelevision ?? false;
    const coverRadius = LumaRadii.cover;
    final interactionInset = !television && item.type == MediaType.video
        ? LumaSpacing.xs
        : 0.0;
    final artworkRadius = coverRadius > interactionInset
        ? coverRadius - interactionInset
        : 0.0;
    final artwork = MediaArtwork(
      item: item,
      useCardThumbnail: item.type == MediaType.video,
      fit: artworkFit ?? BoxFit.cover,
      cacheWidth: heroTag == null ? null : MediaArtwork.heroThumbnailCacheWidth,
      cacheHeight: heroTag != null && item.type == MediaType.video
          ? MediaArtwork.heroThumbnailCacheHeight
          : null,
    );
    final artworkWithHero = heroTag == null
        ? artwork
        : Hero(
            tag: heroTag!,
            flightShuttleBuilder: MediaArtwork.preserveSourceHeroFlight,
            child: artwork,
          );
    return LumaFocusableSurface(
      label: item.title,
      onActivate: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(coverRadius),
      contentPadding: EdgeInsets.all(interactionInset),
      focusNode: focusNode,
      autofocus: autofocus,
      onFocusChange: onFocusChange,
      focusId: focusId,
      focusBorderWidth: focusBorderWidth,
      paintFocusBorder: !television,
      paintHoverFill: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: television ? 16 / 9 : 16 / 10,
            child: _TvCardArtwork(
              television: television,
              borderRadius: BorderRadius.circular(artworkRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  artworkWithHero,
                  if (item.type == MediaType.video && duration.isNotEmpty)
                    Positioned(
                      right: LumaSpacing.xs,
                      bottom: item.progress > 0
                          ? LumaSpacing.sm
                          : LumaSpacing.xs,
                      child: MediaBadge(label: duration),
                    ),
                  if (onFavorite != null)
                    Positioned(
                      right: LumaSpacing.xxs,
                      top: LumaSpacing.xxs,
                      child: LumaFavoriteButton(
                        isFavorite: item.isFavorite,
                        onPressed: onFavorite,
                        overlay: true,
                      ),
                    ),
                  if (item.progress > 0 && item.type == MediaType.video)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: CoverProgressBar(progress: item.progress),
                    ),
                  if (selectionMode)
                    Positioned(
                      left: LumaSpacing.xxs,
                      top: LumaSpacing.xxs,
                      child: MediaSelectionMarker(selected: selected),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: LumaSpacing.xs),
          Text(
            item.title,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: LumaSpacing.xxs),
          Text(
            television
                ? (item.type == MediaType.video
                      ? [
                          item.resolution,
                          item.format.toUpperCase(),
                        ].where((value) => value.isNotEmpty).join(' · ')
                      : '${item.resolution} · 图片')
                : item.type == MediaType.video
                ? '${item.resolution} · ${formatMediaDate(item.addedAt)}'
                : '${item.resolution} · 图片',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvCardArtwork extends StatelessWidget {
  const _TvCardArtwork({
    required this.television,
    required this.borderRadius,
    required this.child,
  });

  final bool television;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) => television
      ? TvArtworkFocus(borderRadius: borderRadius, child: child)
      : LumaCoverLift(
          borderRadius: borderRadius,
          child: ClipRRect(borderRadius: borderRadius, child: child),
        );
}
