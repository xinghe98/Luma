// Loads protected media resources with the active API session.
import 'package:flutter/material.dart';

import '../../app/app_scope.dart';

class AuthenticatedMediaImage extends StatelessWidget {
  const AuthenticatedMediaImage({
    super.key,
    required this.path,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.fullResolution = false,
    this.fadeInDuration,
    this.resizePolicy = ResizeImagePolicy.exact,
    this.onImageLoaded,
  });

  final String path;
  final Widget fallback;
  final BoxFit fit;

  /// 解码目标宽度（设备像素）。列表缩略图应传入以降低内存。
  final int? cacheWidth;
  final int? cacheHeight;

  /// 为 true 时不套用列表默认 cacheWidth，用于全屏原图预览。
  final bool fullResolution;

  /// 首帧到达后淡入；用于原图叠在缩略图上时避免生硬切换。
  final Duration? fadeInDuration;

  /// `fit` avoids stretching a decoded image when both cache dimensions are
  /// constrained (notably the full-screen preview memory budget).
  final ResizeImagePolicy resizePolicy;

  /// Called after the first decoded frame is available.
  final VoidCallback? onImageLoaded;

  @override
  Widget build(BuildContext context) {
    final dependencies = AppScope.maybeOf(context);
    if (path.isEmpty || dependencies == null) return fallback;
    final session = dependencies.apiSession;
    if (session.origin.isEmpty) return fallback;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final int? resolvedWidth;
    if (fullResolution) {
      resolvedWidth = cacheWidth;
    } else {
      // 未指定时按常见列表卡片宽度限制解码；上限对齐服务端 thumbnail_width(640)。
      resolvedWidth = cacheWidth ?? (180 * dpr).round().clamp(1, 640);
    }
    final network = NetworkImage(
      session.resolve(path),
      headers: session.authorizationHeaders,
    );
    final ImageProvider<Object> provider;
    if (resolvedWidth == null && cacheHeight == null) {
      provider = network;
    } else {
      provider = ResizeImage(
        network,
        width: resolvedWidth,
        height: cacheHeight,
        policy: resizePolicy,
      );
    }
    return Image(
      image: provider,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: fullResolution ? FilterQuality.medium : FilterQuality.low,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) {
          _notifyImageLoaded();
          return child;
        }
        if (frame != null) _notifyImageLoaded();
        final fade = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : fadeInDuration;
        if (fade == null || fade <= Duration.zero) {
          return frame == null ? fallback : child;
        }
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: fade,
          curve: Curves.easeOut,
          child: frame == null ? fallback : child,
        );
      },
    );
  }

  void _notifyImageLoaded() {
    final callback = onImageLoaded;
    if (callback == null) return;
    // A cached first frame can be delivered while the parent is building.
    // Deferring avoids setState-during-build in the preview's thumbnail swap.
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  }
}
