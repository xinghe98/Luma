import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app_dependencies.dart';
import 'app/app_metadata.g.dart';
import 'app/app_router.dart';
import 'app/open_source_licenses.dart';
import 'app/app_scope.dart';
import 'app/app_window_controller.dart';
import 'core/theme.dart';
import 'features/player/widgets/mini_player_overlay.dart';
import 'shared/branding/brand_mark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  registerBundledLicenses();
  final imageCache = PaintingBinding.instance.imageCache;
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final logicalShortestSide =
      view.physicalSize.shortestSide / view.devicePixelRatio;
  final isLargeScreen = logicalShortestSide >= 600;
  imageCache.maximumSize = AppWindowController.isWindows ? 200 : 150;
  // Windows 多列和大图预览使用更大缓存；Android 保持既有内存边界。
  imageCache.maximumSizeBytes =
      (AppWindowController.isWindows ? 96 : (isLargeScreen ? 64 : 48)) << 20;
  final dependencies = AppDependencies.create();
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
  LumaApp.production({super.key})
    : dependencies = AppDependencies.create(),
      ownsDependencies = true;

  final AppDependencies dependencies;

  /// 为 true 时依赖由本组件创建，并随组件一起释放。
  final bool ownsDependencies;

  @override
  State<LumaApp> createState() => _LumaAppState();
}

class _LumaAppState extends State<LumaApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(widget.dependencies);
    if (widget.ownsDependencies) {
      unawaited(widget.dependencies.restoreSession());
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
          theme: LumaTheme.light(),
          darkTheme: LumaTheme.dark(),
          themeMode: widget.dependencies.settings.themeMode,
          routerConfig: _router,
          // 小窗叠在路由树之上（含 Navigator 内 Dialog），保证始终最前。
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [
              _LaunchBrandOverlay(child: child ?? const SizedBox.shrink()),
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

class _LaunchBrandOverlayState extends State<_LaunchBrandOverlay> {
  static const _minimumPresentation = Duration(seconds: 1);
  static const _compactBrandHeight = 72.0;
  static const _wideBrandHeight = 180.0;

  Timer? _dismissTimer;
  bool _isVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dismissTimer != null) return;
    // 最短展示时间与资源预缓存并行；不因解码阻塞计时，避免遮罩长期吞掉点击。
    _startDismissTimer();
    final lockup = AssetImage(
      BrandMark.assetFor(
        variant: BrandMarkVariant.horizontal,
        brightness: Theme.of(context).brightness,
      ),
    );
    unawaited(precacheImage(lockup, context).catchError((_) {}));
  }

  void _startDismissTimer() {
    if (!mounted || _dismissTimer != null) return;
    _dismissTimer = Timer(_minimumPresentation, () {
      if (mounted) setState(() => _isVisible = false);
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  /// 按开屏可用宽度选择品牌比例，手机保持克制，Windows 宽屏沿用既有尺寸。
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_isVisible) ExcludeSemantics(child: widget.child) else widget.child,
      if (_isVisible)
        Semantics(
          container: true,
          label: '轻影正在启动',
          child: AbsorbPointer(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final brandHeight =
                      constraints.maxWidth >=
                          LumaLayout.navigationRailBreakpoint
                      ? _wideBrandHeight
                      : _compactBrandHeight;
                  return Center(
                    child: BrandMark(
                      variant: BrandMarkVariant.horizontal,
                      height: brandHeight,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
    ],
  );
}
