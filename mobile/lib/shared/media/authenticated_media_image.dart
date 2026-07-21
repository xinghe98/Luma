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
  });

  final String path;
  final Widget fallback;
  final BoxFit fit;

  /// 解码目标宽度（设备像素）。列表缩略图应传入以降低内存。
  final int? cacheWidth;
  final int? cacheHeight;

  /// 为 true 时不套用列表默认 cacheWidth，用于全屏原图预览。
  final bool fullResolution;

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
    return Image.network(
      session.resolve(path),
      headers: session.authorizationHeaders,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: fullResolution ? FilterQuality.medium : FilterQuality.low,
      cacheWidth: resolvedWidth,
      cacheHeight: cacheHeight,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return fallback;
      },
    );
  }
}
