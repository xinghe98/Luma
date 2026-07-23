import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_dependencies.dart';
import 'app/app_scope.dart';
import 'core/theme.dart';
import 'features/connection/connection_page.dart';
import 'features/shell/app_shell.dart';

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

class LumaApp extends StatelessWidget {
  const LumaApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        dependencies.session,
        dependencies.settings,
        dependencies.restoring,
      ]),
      builder: (context, _) => AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '轻影 Luma',
          theme: LumaTheme.light(),
          darkTheme: LumaTheme.dark(),
          themeMode: dependencies.settings.themeMode,
          home: dependencies.session.isConnected
              ? const AppShell()
              : const ConnectionPage(),
        ),
      ),
    );
  }
}
