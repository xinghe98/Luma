import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app_dependencies.dart';
import 'app/app_router.dart';
import 'app/app_scope.dart';
import 'core/theme.dart';
import 'features/player/widgets/mini_player_overlay.dart';
import 'shared/branding/brand_mark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final imageCache = PaintingBinding.instance.imageCache;
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final logicalShortestSide =
      view.physicalSize.shortestSide / view.devicePixelRatio;
  final isLargeScreen = logicalShortestSide >= 600;
  imageCache.maximumSize = 150;
  // 手机减少纹理驻留量；平板保留更大的缓存，避免宽屏多列反复解码。
  imageCache.maximumSizeBytes = (isLargeScreen ? 64 : 48) << 20;
  runApp(LumaApp.production());
}

class LumaApp extends StatefulWidget {
  /// 使用外部依赖构建应用；依赖生命周期仍由调用方负责。
  const LumaApp({super.key, required this.dependencies})
    : ownsDependencies = false;

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
        ]),
        builder: (context, _) => MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: '轻影 Luma',
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

  Timer? _dismissTimer;
  bool _isVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dismissTimer != null) return;
    final lockup = AssetImage(
      BrandMark.assetFor(
        variant: BrandMarkVariant.horizontal,
        brightness: Theme.of(context).brightness,
      ),
    );
    precacheImage(lockup, context).then<void>(
      (_) => _startDismissTimer(),
      onError: (_, _) => _startDismissTimer(),
    );
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
              child: const Center(
                child: BrandMark(
                  variant: BrandMarkVariant.horizontal,
                  height: 180,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
