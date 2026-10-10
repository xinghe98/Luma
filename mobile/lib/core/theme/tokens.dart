import 'package:flutter/material.dart';

abstract final class LumaColors {
  // 「放映室」调色板：暖调石墨中性色，琥珀色是唯一强调色。
  // 深色与浅色按 Material 角色命名，正文对比度控制在 12–16:1。
  static const darkSurface = Color(0xFF141311);
  static const darkSurfaceDim = Color(0xFF100F0D);
  static const darkSurfaceContainerLowest = Color(0xFF100F0D);
  static const darkSurfaceContainerLow = Color(0xFF191816);
  static const darkSurfaceContainer = Color(0xFF1E1C19);
  static const darkSurfaceContainerHigh = Color(0xFF282622);
  static const darkSurfaceContainerHighest = Color(0xFF322F2A);
  static const darkSurfaceBright = Color(0xFF3A3631);
  static const darkOnSurface = Color(0xFFE6E0D6);
  static const darkOnSurfaceVariant = Color(0xFFB3ACA0);
  static const darkOutline = Color(0xFF8C857A);
  static const darkOutlineVariant = Color(0xFF48443C);
  static const darkPrimary = Color(0xFFF0B43C);
  static const darkOnPrimary = Color(0xFF2A1C00);
  static const darkPrimaryContainer = Color(0xFF4A3810);
  static const darkOnPrimaryContainer = Color(0xFFFFDFA3);
  static const darkSecondary = Color(0xFFCDC4B6);
  static const darkOnSecondary = Color(0xFF2E2A23);
  static const darkSecondaryContainer = Color(0xFF3A362F);
  static const darkOnSecondaryContainer = Color(0xFFEDE6DA);
  static const darkTertiary = Color(0xFFA9C6D4);
  static const darkOnTertiary = Color(0xFF0F2A36);
  static const darkTertiaryContainer = Color(0xFF27404C);
  static const darkOnTertiaryContainer = Color(0xFFD5EAF5);
  static const darkError = Color(0xFFFFB4A9);
  static const darkOnError = Color(0xFF561E16);
  static const darkErrorContainer = Color(0xFF5E1B13);
  static const darkOnErrorContainer = Color(0xFFFFDAD4);
  static const darkInverseSurface = Color(0xFFE6E0D6);
  static const darkOnInverseSurface = Color(0xFF2E2B26);
  static const darkInversePrimary = Color(0xFF835700);
  static const darkSuccess = Color(0xFF9CCFA6);
  static const darkWarning = Color(0xFFF2B08A);

  static const lightSurface = Color(0xFFF5F2EC);
  static const lightSurfaceDim = Color(0xFFE3DED5);
  static const lightSurfaceContainerLowest = Color(0xFFFDFCF9);
  static const lightSurfaceContainerLow = Color(0xFFF9F7F2);
  static const lightSurfaceContainer = Color(0xFFFCFBF8);
  static const lightSurfaceContainerHigh = Color(0xFFEDE9E1);
  static const lightSurfaceContainerHighest = Color(0xFFE5E0D6);
  static const lightSurfaceBright = Color(0xFFFDFCF9);
  static const lightOnSurface = Color(0xFF1F1C17);
  static const lightOnSurfaceVariant = Color(0xFF58524A);
  static const lightOutline = Color(0xFF756E63);
  static const lightOutlineVariant = Color(0xFFD6CFC2);
  static const lightPrimary = Color(0xFF835700);
  static const lightOnPrimary = Color(0xFFFFF8EE);
  static const lightPrimaryContainer = Color(0xFFF6DEAB);
  static const lightOnPrimaryContainer = Color(0xFF2A1D00);
  static const lightSecondary = Color(0xFF685F52);
  static const lightOnSecondary = Color(0xFFFFF8EE);
  static const lightSecondaryContainer = Color(0xFFEAE3D6);
  static const lightOnSecondaryContainer = Color(0xFF2A251D);
  static const lightTertiary = Color(0xFF3B6170);
  static const lightOnTertiary = Color(0xFFF2FAFF);
  static const lightTertiaryContainer = Color(0xFFCFE6F2);
  static const lightOnTertiaryContainer = Color(0xFF0E2732);
  static const lightError = Color(0xFFB02A1F);
  static const lightOnError = Color(0xFFFFF8F6);
  static const lightErrorContainer = Color(0xFFFFDAD4);
  static const lightOnErrorContainer = Color(0xFF410002);
  static const lightInverseSurface = Color(0xFF322E28);
  static const lightOnInverseSurface = Color(0xFFF2EDE4);
  static const lightInversePrimary = Color(0xFFF0B43C);
  static const lightSuccess = Color(0xFF2D683C);
  static const lightWarning = Color(0xFF94420F);

  // 与亮暗无关的常量：开屏品牌色与播放器墨色。
  /// 品牌石墨/画框白；开屏品牌色，不作界面大面积底色。
  static const brandGraphite = Color(0xFF1F1E1B);
  static const brandPaper = Color(0xFFF7F5F0);

  /// Logo 半日琥珀；仅限开屏与品牌点缀，不作文字色或大面积底色。
  static const brandAmber = Color(0xFFF5B800);
  static const playerInk = Color(0xFF0E0D0B);
  static const onPlayerInk = Color(0xFFECE6DC);
  static const onPlayerInkMuted = Color(0xFFB8B0A4);
  static const badgeScrim = Color(0xB80E0D0B);
  static const shadow = Color(0xFF0E0D0B);
  static const scrim = Color(0xFF0E0D0B);
}

/// 交互态透明度 token；装饰性遮罩的停靠值见 [LumaGradients]。
abstract final class LumaOpacity {
  static const hover = 0.06;
  static const focus = 0.10;
  static const pressed = 0.10;

  /// 导航选中胶囊等低强调选中底色。
  static const selected = 0.12;
  static const disabled = 0.38;
  static const divider = 1.0;
  static const scrim = 0.72;
}

/// 统一的封面/详情遮罩渐变，替代各页面复制的多套停靠值。
abstract final class LumaGradients {
  /// 底部控制层遮罩：顶部透明过渡到底部 85% 墨色。
  static LinearGradient bottomScrim(Color ink) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      ink.withValues(alpha: 0),
      ink.withValues(alpha: 0),
      ink.withValues(alpha: 0.55),
      ink.withValues(alpha: 0.85),
    ],
    stops: const [0, 0.35, 0.7, 1],
  );

  /// 详情首屏顶部到底部的淡出：背景图融入页面底色。
  static LinearGradient heroFade(Color surface) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      surface.withValues(alpha: 0),
      surface.withValues(alpha: 0.55),
      surface.withValues(alpha: 0.92),
      surface,
    ],
    stops: const [0, 0.40, 0.68, 1],
  );

  /// TV 详情横向淡出：左侧页面底色过渡到右侧背景图。
  static LinearGradient sideFade(Color surface) => LinearGradient(
    colors: [
      surface,
      surface.withValues(alpha: 0.92),
      surface.withValues(alpha: 0.4),
      surface.withValues(alpha: 0),
    ],
    stops: const [0, 0.38, 0.62, 1],
  );
}

abstract final class LumaArtworkColors {
  static const palettes = <List<Color>>[
    [Color(0xFF6E6457), Color(0xFF2F2B26), Color(0xFFC9B48A)],
    [Color(0xFF7A6A4F), Color(0xFF332E25), Color(0xFFD9BE8E)],
    [Color(0xFF5F7079), Color(0xFF272E33), Color(0xFFB9CDD6)],
    [Color(0xFF6E6055), Color(0xFF2E2924), Color(0xFFD4B9A0)],
    [Color(0xFF66705A), Color(0xFF2B2E26), Color(0xFFC2CDA4)],
  ];
}

abstract final class LumaTypography {
  static const fontFamily = 'MiSans';
  static const fontFamilyFallback = <String>['sans-serif'];

  static TextTheme buildTextTheme(TextTheme base) {
    final themed = base.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
    // 阶梯按「放映室」层级重排，字距统一归零由字重与行高区分层级。
    return themed.copyWith(
      displayLarge: themed.displayLarge?.copyWith(
        fontSize: 48,
        fontWeight: FontWeight.w600,
        height: 1.1,
        letterSpacing: 0,
      ),
      displayMedium: themed.displayMedium?.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        height: 1.15,
        letterSpacing: 0,
      ),
      displaySmall: themed.displaySmall?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
      headlineLarge: themed.headlineLarge?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
      ),
      headlineMedium: themed.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0,
      ),
      headlineSmall: themed.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleLarge: themed.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: 0,
      ),
      titleSmall: themed.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
        letterSpacing: 0,
      ),
      bodyLarge: themed.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.55,
        letterSpacing: 0,
      ),
      bodyMedium: themed.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.55,
        letterSpacing: 0,
      ),
      bodySmall: themed.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.5,
        letterSpacing: 0,
      ),
      labelLarge: themed.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 0,
      ),
      labelMedium: themed.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 0,
      ),
      labelSmall: themed.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 0,
      ),
    );
  }
}

abstract final class LumaLayout {
  static const contentMaxWidth = 1280.0;
  static const detailMaxWidth = 1160.0;
  static const formMaxWidth = 520.0;
  static const navigationRailBreakpoint = 840.0;
  static const extendedRailBreakpoint = 1100.0;

  /// 宽屏侧栏收起/展开宽度；展开态在 [extendedRailBreakpoint] 以上启用。
  static const navigationRailWidth = 88.0;
  static const navigationRailExtendedWidth = 232.0;
  static const detailTwoColumnBreakpoint = 760.0;
  static const horizontalCardWidth = 232.0;
  static const pagePaddingH = 20.0;
  static const pagePaddingTabletH = 28.0;
  static const pagePaddingWideH = 32.0;
  static const pagePaddingTop = 12.0;
  static const pagePaddingBottom = 40.0;

  /// 按钮外观高度；触控区由主题的 padded 补足到 [minTapTarget]。
  static const buttonHeight = 40.0;
  static const navigationBarHeight = 64.0;
  static const minTapTarget = 48.0;
  static const inputHeight = 52.0;
  static const actionWidthBreakpoint = 600.0;
  static const actionMaxWidth = 280.0;

  /// 宽屏短操作（断开、应用等）的宽度上限。
  static const shortActionMaxWidth = 240.0;

  static const scrollCacheExtent = 320.0;

  static EdgeInsets pagePadding({
    double top = pagePaddingTop,
    double bottom = pagePaddingBottom,
  }) => EdgeInsets.fromLTRB(pagePaddingH, top, pagePaddingH, bottom);

  /// 根据可用宽度返回统一页面边距，宽屏只增加呼吸感而不改变内容结构。
  static double pageHorizontalPadding(double width) => width >= 840
      ? pagePaddingWideH
      : width >= 600
      ? pagePaddingTabletH
      : pagePaddingH;

  static int gridColumns(double width) => width >= 1200
      ? 5
      : width >= 900
      ? 4
      : width >= 600
      ? 3
      : 2;

  /// 2:3 海报网格列数；与货架、集合页共用同一断点表。
  static int posterColumns(double width) => width < 360
      ? 2
      : width < 600
      ? 3
      : width < 840
      ? 4
      : width < 1100
      ? 5
      : width < 1400
      ? 6
      : 7;

  /// 海报货架卡片宽度；空间越宽卡片越大，但不随容器无限拉伸。
  static double posterShelfWidth(double width) => width >= 1200
      ? 176
      : width >= 600
      ? 160
      : 140;
}

/// TV 十英尺界面的布局常量；仅在设备形态为 television 的分支使用。
abstract final class LumaTvLayout {
  /// 四边安全边距占视口比例，避免电视过扫描裁切内容与焦点。
  static const safeAreaRatio = 0.05;
  static const navigationWidth = 224.0;
  static const navigationWidthCompact = 80.0;
  static const focusStroke = 3.0;
  static const controlMinHeight = 56.0;
  static const cardSpacing = 24.0;
  static const posterMinWidth = 160.0;
  static const landscapeCardMinWidth = 256.0;
  static const featureMinWidth = 760.0;
  static const contentMaxWidth = 1600.0;
  static const pagePadding = 32.0;

  /// 详情首屏进入左右分栏的局部宽度下限。
  static const detailSplitWidth = 900.0;

  /// 详情首屏横幅的最小高度，保证标题与操作区可读。
  static const heroMinHeight = 288.0;

  /// 按扣除导航与边距后的局部宽度计算规则网格列数，夹在 1–5 列。
  static int gridColumns(double width, {double minItemWidth = posterMinWidth}) {
    final columns = ((width + cardSpacing) / (minItemWidth + cardSpacing))
        .floor();
    return columns.clamp(1, 5);
  }

  /// TV 页头在局部宽度不足时重排为上下两行；文字缩放会同步收窄阈值。
  static bool compactHeader(BoxConstraints constraints, TextScaler scaler) =>
      constraints.maxWidth < 640 * scaler.scale(18) / 18;
}

abstract final class LumaSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class LumaRadii {
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const extraLarge = 24.0;
  static const cover = 10.0;
  static const badge = 999.0;
}

abstract final class LumaIconSize {
  static const status = 18.0;
  static const inline = 22.0;

  /// 普通端图标按钮内的图标；比 [action] 小一号，配合 40 外观。
  static const compact = 20.0;
  static const action = 24.0;
  static const prominent = 28.0;
  static const emptyState = 40.0;
}

abstract final class LumaStroke {
  static const hairline = 1.0;
  static const focused = 1.5;
}

abstract final class LumaMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration navigation = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 250);
  static const Curve standard = Curves.easeOutCubic;

  static Duration forContext(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
