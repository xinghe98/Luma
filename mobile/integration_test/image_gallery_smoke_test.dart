// 在隔离 Windows 窗口验证图片库切图与删除，复用真实控件、鉴权解码和内存仓储。
// 只访问本机测试服务器，截图不含其他窗口；退出时释放依赖和 HTTP 监听。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_navigation.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/details/dialogs/image_preview_dialog.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/shared/media/image_gallery_controller.dart';

import 'support/tv_smoke_repositories.dart';
import 'support/tv_smoke_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    (size: const Size(390, 844), dark: false),
    (size: const Size(1280, 800), dark: true),
  ]) {
    testWidgets('图片库原生切图与缩放 ${scenario.size} dark=${scenario.dark}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final server = TvSmokeServer(videoBytes: const [], imageCount: 20);
      final session = ApiSession();
      final dependencies = AppDependencies(
        mediaRepository: TvSmokeMediaRepository(),
        connectionService: TvSmokeConnectionService(session),
        apiSession: session,
      );
      final surface = GlobalKey();
      ImageGalleryController? gallery;
      try {
        await server.start();
        session.update(origin: server.origin, token: kTvSmokeToken);
        await tester.pumpWidget(
          RepaintBoundary(
            key: surface,
            child: AppScope(
              dependencies: dependencies,
              child: MaterialApp(
                theme: scenario.dark ? LumaTheme.dark() : LumaTheme.light(),
                home: Builder(
                  builder: (context) => LibraryPage(
                    type: MediaType.image,
                    pageSize: 18,
                    onOpenSearch: () {},
                    onOpenMedia: (item, {heroTag}) =>
                        context.openImagePreview(item, heroTag: heroTag),
                    onOpenImageGallery: (value, {heroTag}) {
                      gallery = value;
                      return context.openImagePreview(
                        value.currentItem!,
                        gallery: value,
                        heroTag: heroTag,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await _waitFor(
          tester,
          () async =>
              find.byKey(const ValueKey('image-0')).evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('image-0')));
        await tester.pumpAndSettle();
        await _expectDecodedImage(tester, 0);
        expect(gallery!.currentItem!.id, 'image-0');

        await tester.tap(find.byTooltip('下一张'));
        await tester.pumpAndSettle();
        await _expectDecodedImage(tester, 1);
        expect(gallery!.currentItem!.id, 'image-1');

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        await _expectDecodedImage(tester, 2);
        expect(gallery!.currentItem!.id, 'image-2');

        await tester.drag(
          find.byType(InteractiveViewer),
          const Offset(-220, 0),
        );
        await tester.pumpAndSettle();
        await _expectDecodedImage(tester, 3);
        expect(gallery!.currentItem!.id, 'image-3');

        await tester.tap(find.byTooltip('放大'));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(InteractiveViewer),
          const Offset(-120, 0),
        );
        await tester.pumpAndSettle();
        expect(gallery!.currentItem!.id, 'image-3');
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          greaterThan(1),
        );

        await tester.tap(find.byTooltip('上一张'));
        await tester.pumpAndSettle();
        await _expectDecodedImage(tester, 2);
        expect(gallery!.currentItem!.id, 'image-2');
        expect(
          tester
              .widget<InteractiveViewer>(find.byType(InteractiveViewer))
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          closeTo(1, 0.001),
        );
        await _capture(
          surface,
          'gallery-${scenario.size.width.toInt()}-${scenario.dark ? 'dark' : 'light'}',
        );

        await tester.tap(find.byTooltip('删除图片'));
        await tester.pumpAndSettle();
        await _capture(surface, 'delete-confirm-${scenario.size.width.toInt()}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(gallery!.currentItem!.id, 'image-2');
        expect(dependencies.media.isDeleted('image-2'), isFalse);
        await tester.tap(find.byTooltip('删除图片'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('永久删除'));
        await tester.pumpAndSettle();
        expect(dependencies.media.isDeleted('image-2'), isTrue);
        expect(gallery!.currentItem!.id, 'image-3');
        await _expectDecodedImage(tester, 3);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _waitFor(
          tester,
          () async => find.byType(ImagePreviewDialog).evaluate().isEmpty,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ImagePreviewDialog), findsNothing);
        expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
        expect(
          find.byKey(const ValueKey('image-0')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('image-2')), findsNothing);
        await tester.tap(find.byTooltip('选择图片'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('image-0')));
        await tester.tap(find.byKey(const ValueKey('image-1')));
        await tester.pumpAndSettle();
        expect(find.text('已选 2 项'), findsOneWidget);
        await _capture(surface, 'delete-selection-${scenario.size.width.toInt()}');
        await tester.tap(find.text('删除(2)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('永久删除'));
        await tester.pumpAndSettle();
        expect(dependencies.media.isDeleted('image-0'), isTrue);
        expect(dependencies.media.isDeleted('image-1'), isTrue);
        expect(find.byKey(const ValueKey('image-0')), findsNothing);
        expect(find.byKey(const ValueKey('image-1')), findsNothing);
        expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
        expect(server.authFailures, 0);
        expect(tester.takeException(), isNull);
        debugPrint(
          'NATIVE_GALLERY_OK: ${scenario.size} tap/key/swipe/zoom/pixels/close/delete',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        dependencies.dispose();
        await server.close();
      }
    });
  }
}

/// 等待可观察状态，避免把真实网络解码时间写成固定延迟。
Future<void> _waitFor(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(await condition(), isTrue, reason: '图片预览状态未在期限内就绪');
}

/// 检查实际解码后的原图像素，切换模型成功但仍显示旧图片也会失败。
Future<void> _expectDecodedImage(WidgetTester tester, int index) async {
  final expected = [
    40 + (index * 37) % 200,
    60 + (index * 53) % 180,
    90 + (index * 71) % 160,
  ];
  await _waitFor(tester, () async {
    final images = tester
        .widgetList<RawImage>(
          find.descendant(
            of: find.byType(ImagePreviewDialog),
            matching: find.byType(RawImage),
          ),
        )
        .where((widget) => widget.image != null)
        .toList();
    if (images.length < 2) return false;
    for (final widget in images) {
      final bytes = await widget.image!.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (bytes == null) return false;
      for (var channel = 0; channel < 3; channel++) {
        if ((bytes.getUint8(channel) - expected[channel]).abs() > 2) {
          return false;
        }
      }
    }
    return true;
  });
}

/// 保存应用自己的画面，供核对窄屏与宽屏控件布局。
Future<void> _capture(GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      '${Directory.systemTemp.path}/luma_image_gallery_smoke',
    );
    await directory.create(recursive: true);
    final path = '${directory.path}/$name.png';
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    debugPrint('GALLERY_SCREENSHOT: $path');
  } finally {
    image.dispose();
  }
}
