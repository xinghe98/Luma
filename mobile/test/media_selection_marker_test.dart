// 验证共用勾选标记的实际像素不会透出封面，覆盖手机、宽屏及浅深主题。
// 使用独立绘制边界读取中心像素，截图资源在每次读取后立即释放。
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/shared/media/media_selection_marker.dart';

void main() {
  for (final size in [const Size(320, 700), const Size(1280, 800)]) {
    for (final dark in [false, true]) {
      for (final dpi in [1.0, 1.25, 1.5]) {
        testWidgets('勾选底色隔离封面 ${size.width} dark=$dark dpi=$dpi', (
          tester,
        ) async {
          tester.view.devicePixelRatio = dpi;
          tester.view.physicalSize = size * dpi;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = dark ? LumaTheme.dark() : LumaTheme.light();
          final boundaryKey = GlobalKey();
          for (final selected in [false, true]) {
            List<int>? reference;
            for (final artwork in [
              LumaColors.brandPaper,
              LumaColors.playerInk,
              theme.colorScheme.primary,
            ]) {
              await tester.pumpWidget(
                MaterialApp(
                  theme: theme,
                  home: Scaffold(
                    body: Center(
                      child: RepaintBoundary(
                        key: boundaryKey,
                        child: SizedBox.square(
                          dimension: 48,
                          child: ColoredBox(
                            color: artwork,
                            child: Center(
                              child: MediaSelectionMarker(selected: selected),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final pixels = await tester.runAsync(
                () => _centerPixels(boundaryKey),
              );
              expect(pixels, isNotNull);
              if (reference != null) {
                expect(
                  pixels,
                  orderedEquals(reference),
                  reason: '勾选标记中心应由自身底色与勾号组成，不能透出封面',
                );
              }
              reference = pixels;
              expect(tester.takeException(), isNull);
            }
          }
        });
      }
    }
  }
}

/// 读取标记中心 12dp 方形区域，避开圆周抗锯齿与封面相接的像素。
Future<List<int>> _centerPixels(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final result = <int>[];
    for (var y = image.height ~/ 2 - 12; y < image.height ~/ 2 + 12; y++) {
      for (var x = image.width ~/ 2 - 12; x < image.width ~/ 2 + 12; x++) {
        result.add(bytes.getUint32((y * image.width + x) * 4));
      }
    }
    return result;
  } finally {
    image.dispose();
  }
}
