import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_dependencies.dart';
import 'app/app_router.dart';
import 'app/app_scope.dart';
import 'core/theme.dart';
import 'shared/branding/brand_mark.dart';
import 'package:go_router/go_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final imageCache = PaintingBinding.instance.imageCache;
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final logicalShortestSide =
      view.physicalSize.shortestSide / view.devicePixelRatio;
  final isLargeScreen = logicalShortestSide >= 600;
  imageCache.maximumSize = 150;
  // 手机减少纹理驻留量；平板保留更大的缓存，避免宽屏多列反复解码。
  imageCache.maximumSizeBytes = (isLargeScreen ? 64 : 48) << 20;
  final dependencies = AppDependencies.create();
  runApp(LumaApp(dependencies: dependencies));
  unawaited(dependencies.restoreSession());
}

class LumaApp extends StatefulWidget {
  const LumaApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<LumaApp> createState() => _LumaAppState();
}

class _LumaAppState extends State<LumaApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(widget.dependencies);
  }

  @override
  void dispose() {
    _router.dispose();
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
          theme: LumaTheme.light(),
          darkTheme: LumaTheme.dark(),
          themeMode: widget.dependencies.settings.themeMode,
          routerConfig: _router,
          builder: (context, child) => _LaunchBrandOverlay(
            child: child ?? const SizedBox.shrink(),
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
      widget.child,
      if (_isVisible)
        IgnorePointer(
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
    ],
  );
}
