// TV 页面背景铺满可用区域；内容保留有上限的安全边距与既有最大宽度。
// 供 shell、连接和根层详情/集合页复用，每个路由最多包一次；
// 播放器画面与控制层的安全区不经过此组件。
import 'package:flutter/material.dart';

import '../../core/theme.dart';

class TvContentFrame extends StatelessWidget {
  /// [maxWidth] 默认采用 TV 内容宽度；表单和详情可提供各自的宽度上限。
  const TvContentFrame({
    super.key,
    required this.child,
    this.maxWidth = LumaTvLayout.contentMaxWidth,
    this.backgroundColor,
  });

  final Widget child;
  final double maxWidth;

  /// 页面有专属背景时同步绘制边缘，缺省沿用当前主题的页面底色。
  final Color? backgroundColor;

  /// 绘制完整页面底色，再限制内容留白，避免大视口出现透明黑边或过宽边框。
  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return ColoredBox(
      color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: (viewport.width * LumaTvLayout.safeAreaRatio).clamp(
            0.0,
            LumaSpacing.lg,
          ),
          vertical: (viewport.height * LumaTvLayout.safeAreaRatio).clamp(
            0.0,
            LumaSpacing.lg,
          ),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}
