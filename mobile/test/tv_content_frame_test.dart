// TV 页面框架回归：验证小视口到 4K 的安全留白、内容限宽与边缘实际像素。
// 使用真实 Material 页面和绘制边界，不接触会话；每例释放图像并恢复测试视口。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/shared/layout/tv_content_frame.dart';

void main() {
  for (final size in const [
    Size(320, 640),
    Size(390, 844),
    Size(768, 1024),
    Size(1024, 768),
    Size(960, 640),
    Size(1280, 800),
    Size(1920, 1080),
    Size(3840, 2160),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('TV 页面背景铺满且安全留白不随大屏无限扩大 $size dark=$dark', (tester) async {
        _setViewport(tester, size);
        final theme = dark ? LumaTheme.dark() : LumaTheme.light();
        final boundaryKey = GlobalKey();
        const pageKey = ValueKey('tv-test-page');
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: boundaryKey,
              child: const TvContentFrame(
                child: Scaffold(
                  key: pageKey,
                  body: Center(child: Text('页面内容')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pageRect = tester.getRect(find.byKey(pageKey));
        expect(pageRect.top, greaterThan(0));
        expect(pageRect.top, lessThanOrEqualTo(LumaSpacing.lg));
        expect(
          size.height - pageRect.bottom,
          lessThanOrEqualTo(LumaSpacing.lg),
        );
        expect(pageRect.width, lessThanOrEqualTo(LumaLayout.contentMaxWidth));
        if (size.width <= LumaLayout.contentMaxWidth) {
          expect(pageRect.left, lessThanOrEqualTo(LumaSpacing.lg));
          expect(
            size.width - pageRect.right,
            lessThanOrEqualTo(LumaSpacing.lg),
          );
        }
        await _expectPaintedEdges(
          tester,
          boundaryKey,
          theme.scaffoldBackgroundColor,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('浅色主题下作品页专属底色延伸到屏幕边缘', (tester) async {
    _setViewport(tester, const Size(1920, 1080));
    const detailBackground = Color(0xff172033);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: LumaTheme.light(),
        home: RepaintBoundary(
          key: boundaryKey,
          child: const TvContentFrame(
            backgroundColor: detailBackground,
            child: Scaffold(backgroundColor: detailBackground),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _expectPaintedEdges(tester, boundaryKey, detailBackground);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// 按原始像素采样四角与边缘，避免缩放到半个像素时产生透明的抗锯齿边缘。
Future<void> _expectPaintedEdges(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Color expected,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final expectedArgb = expected.toARGB32();
      for (final point in [
        (0, 0),
        (image.width - 1, 0),
        (0, image.height - 1),
        (image.width - 1, image.height - 1),
        (image.width ~/ 2, 0),
        (image.width ~/ 2, image.height - 1),
      ]) {
        final offset = (point.$2 * image.width + point.$1) * 4;
        expect(
          [
            for (var channel = 0; channel < 4; channel++)
              pixels.getUint8(offset + channel),
          ],
          [
            (expectedArgb >> 16) & 255,
            (expectedArgb >> 8) & 255,
            expectedArgb & 255,
            255,
          ],
          reason: '边缘 $point 必须绘制不透明页面底色',
        );
      }
    } finally {
      image.dispose();
    }
  });
}
