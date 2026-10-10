import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app_dependencies.dart';
import 'app/app_device_profile.dart';
import 'app/app_metadata.g.dart';
import 'app/app_router.dart';
import 'app/open_source_licenses.dart';
import 'app/app_scope.dart';
import 'app/app_window_controller.dart';
import 'core/theme.dart';
import 'core/theme/tv_theme.dart';
import 'features/player/widgets/mini_player_overlay.dart';
import 'shared/branding/brand_mark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  registerBundledLicenses();
  final deviceProfile = await resolveAppDeviceProfile();
  final imageCache = PaintingBinding.instance.imageCache;
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final logicalShortestSide =
      view.physicalSize.shortestSide / view.devicePixelRatio;
  final isLargeScreen = logicalShortestSide >= 600;
  imageCache.maximumSize = AppWindowController.isWindows ? 200 : 150;
  // Windows 多列和大图预览使用更大缓存；TV 固定 64MB，手机按屏幕大小保留既有边界。
  imageCache.maximumSizeBytes =
      (AppWindowController.isWindows
          ? 96
          : (deviceProfile.isTelevision || isLargeScreen ? 64 : 48)) <<
      20;
  final dependencies = AppDependencies.create(deviceProfile: deviceProfile);
  await dependencies.initialize();
  final appWindow = AppWindowController();
  await appWindow.initialize();
  runApp(LumaApp(dependencies: dependencies, ownsDependencies: true));
}

class LumaApp extends StatefulWidget {
  /// 使用指定依赖构建应用；仅在 [ownsDependencies] 为 true 时随应用释放。
  const LumaApp({
    super.key,
    required this.dependencies,
    this.ownsDependencies = false,
  });

  /// 创建并持有生产依赖，应用卸载时会统一释放。
  LumaApp.production({
    super.key,
    AppDeviceProfile deviceProfile = AppDeviceProfile.standard,
  }) : dependencies = AppDependencies.create(deviceProfile: deviceProfile),
       ownsDependencies = true;

  final AppDependencies dependencies;

  /// 为 true 时依赖由本组件创建，并随组件一起释放。
  final bool ownsDependencies;

  @override
  State<LumaApp> createState() => _LumaAppState();
}

class _LumaAppState extends State<LumaApp> {
  late final GoRouter _router;
  late final ThemeData _lightTheme;
  late final ThemeData _darkTheme;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(widget.dependencies);
    // TV 在既有主题上放大文字与控件，主题对象只构建一次。
    final isTelevision = widget.dependencies.deviceProfile.isTelevision;
    _lightTheme = isTelevision
        ? applyTvTheme(LumaTheme.light())
        : LumaTheme.light();
    _darkTheme = isTelevision
        ? applyTvTheme(LumaTheme.dark())
        : LumaTheme.dark();
    if (widget.ownsDependencies) {
      unawaited(widget.dependencies.restoreSession());
      unawaited(widget.dependencies.settings.restoreThemeMode());
    }
  }
  @override
  void dispose() {
    _router.dispose();
    if (widget.ownsDependencies) widget.dependencies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: widget.dependencies,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.dependencies.session,
          widget.dependencies.settings,
          widget.dependencies.restoring,
          if (widget.dependencies.proxy != null) widget.dependencies.proxy!,
        ]),
        builder: (context, _) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: AppMetadata.productName,
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN')],
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: widget.dependencies.settings.themeMode,
          routerConfig: _router,
          // 小窗叠在路由树之上（含 Navigator 内 Dialog），保证始终最前。
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [
              _LaunchBrandOverlay(child: child ?? const SizedBox.shrink()),
              // TV 没有小窗播放：退出播放器即结束播放会话。
              if (!widget.dependencies.deviceProfile.isTelevision)
                MiniPlayerOverlay(
                  session: widget.dependencies.playerSession,
                  onExpand: (mediaId) => _router.pushNamed<void>(
                    AppRoute.player,
                    pathParameters: {'mediaId': mediaId},
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchBrandOverlay extends StatefulWidget {
  const _LaunchBrandOverlay({required this.child});

  final Widget child;

  @override
  State<_LaunchBrandOverlay> createState() => _LaunchBrandOverlayState();
}

class _LaunchBrandOverlayState extends State<_LaunchBrandOverlay>
    with TickerProviderStateMixin {
  // MG 片头约 1.8s：展示时长覆盖动画 + 末帧定格，随后整屏淡出。
  static const _minimumPresentation = Duration(milliseconds: 2600);
  static const _exitDuration = Duration(milliseconds: 280);

  // 退场沿用 FadeTransition；MG 片头自身完成入场动效，不再需要额外 entrance 曲线。
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: _exitDuration,
  );
  late final Animation<double> _exitFade = _exit.drive(
    Tween<double>(begin: 1, end: 0),
  );

  Timer? _dismissTimer;
  bool _isVisible = true;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dismissTimer != null) return;
    // 减少动画时退场瞬时完成；MG 片头由 _reducedMotion 降级为静态横版 Logo。
    if (MediaQuery.disableAnimationsOf(context)) {
      _reducedMotion = true;
      _exit.duration = Duration.zero;
    }
    // 最短展示时间与资源预缓存并行；不因解码阻塞计时，避免遮罩长期吞掉点击。
    _startDismissTimer();
    final brightness = MediaQuery.platformBrightnessOf(context);
    unawaited(
      precacheImage(
        const AssetImage('assets/mg/luma-splash.webp'),
        context,
      ).catchError((_) {}),
    );
    unawaited(
      precacheImage(
        const AssetImage('assets/mg/luma-splash-wide.webp'),
        context,
      ).catchError((_) {}),
    );
    final lockup = AssetImage(
      BrandMark.assetFor(
        variant: BrandMarkVariant.horizontal,
        brightness: brightness,
      ),
    );
    unawaited(precacheImage(lockup, context).catchError((_) {}));
  }

  void _startDismissTimer() {
    if (!mounted || _dismissTimer != null) return;
    _dismissTimer = Timer(_minimumPresentation, () {
      if (!mounted) return;
      // 最短展示结束后整屏淡出，动画完成才移除遮罩并交还焦点。
      unawaited(
        _exit.forward().then((_) {
          if (!mounted) return;
          setState(() => _isVisible = false);
          _grantContentInitialFocus();
        }),
      );
    });
  }

  /// 解除遮罩后先落实路由重挂载产生的 autofocus；没有具体控件持焦时才遍历。
  /// 避免通用遍历把连接页指定的地址闸门覆盖成更靠前的代理按钮。
  void _grantContentInitialFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isVisible) return;
      final manager = FocusManager.instance;
      manager.applyFocusChangesIfNeeded();
      final primary = manager.primaryFocus;
      if (primary != null && primary is! FocusScopeNode) return;
      FocusScope.of(context).nextFocus();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _exit.dispose();
    super.dispose();
  }

  /// 开屏按可用宽度挑选 MG 片头（竖版/横版），宽屏与 TV 使用横版构图。
  /// 动画只播一次，片头本身即品牌入场动效，退场仍走整屏淡出。
  @override
  Widget build(BuildContext context) {
    // 开屏底色为品牌画框白（略暖的米白），MG 片头换为深色笔画版本后在其上清晰可读。
    const background = LumaColors.brandPaper;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 可见期间同时阻断指针、语义和键盘焦点/快捷键，遥控器不会操作被遮住的页面。
        if (_isVisible)
          ExcludeFocus(child: ExcludeSemantics(child: widget.child))
        else
          widget.child,
        if (_isVisible)
          Semantics(
            container: true,
            label: '轻影正在启动',
            child: AbsorbPointer(
              child: FadeTransition(
                opacity: _exitFade,
                child: ColoredBox(
                  color: background,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide =
                          constraints.maxWidth >=
                          LumaLayout.navigationRailBreakpoint;
                      if (_reducedMotion) {
                        // 系统减少动画：退化为浅色横版 Logo，与白底保持一致。
                        return Center(
                          child: Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(brightness: Brightness.light),
                            child: BrandMark(
                              variant: BrandMarkVariant.horizontal,
                              height: wide ? 180 : 72,
                            ),
                          ),
                        );
                      }
                      return RepaintBoundary(
                        child: _SplashAnimation(
                          wide: wide,
                          constraints: constraints,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 播放品牌 MG 片头的动画层；动画在画布内居中、contain，不拉伸不裁切。
class _SplashAnimation extends StatelessWidget {
  const _SplashAnimation({required this.wide, required this.constraints});

  final bool wide;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final asset = wide
        ? 'assets/mg/luma-splash-wide.webp'
        : 'assets/mg/luma-splash.webp';
    // 宽屏给动画约 62% 可用宽、窄屏约 78%；纵向限高防顶满。
    final maxWidth = constraints.maxWidth * (wide ? 0.62 : 0.78);
    final maxHeight = constraints.maxHeight * (wide ? 0.5 : 0.34);
    return Center(
      child: Image.asset(
        asset,
        width: maxWidth,
        height: maxHeight,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
