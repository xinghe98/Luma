// 验证图片预览跨端切图、缩放、分页等待和退出；使用内存会话隔离网络与凭据。
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/details/dialogs/image_preview_dialog.dart';
import 'package:luma/features/details/widgets/image_preview_navigation.dart';
import 'package:luma/shared/media/image_gallery_controller.dart';

void main() {
  List<MediaItem> galleryItems({int count = 3}) => buildMediaFixtures()
      .where((entry) => entry.type == MediaType.image)
      .take(count)
      .toList();

  /// 打开预览并泵到静止；[result] 传入时由其带回对话框返回值，
  /// 避免调用方在等待打开的同一个 future 上卡住。
  Future<void> openGallery(
    WidgetTester tester,
    List<MediaItem> items,
    ImageGalleryController gallery, {
    Size surface = const Size(390, 844),
    String? heroTag,
    Completer<ImagePreviewAction?>? result,
    bool dark = false,
    double dpi = 1,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = surface * dpi;
    tester.view.devicePixelRatio = dpi;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final completer = result ?? Completer<ImagePreviewAction?>();
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? LumaTheme.dark() : LumaTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: heroTag == null
                  ? const SizedBox.shrink()
                  : Hero(
                      tag: heroTag,
                      child: const SizedBox(width: 40, height: 40),
                    ),
            ),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showImagePreviewDialog(
        context,
        items.firstWhere((item) => item.id == gallery.currentItem.id),
        heroTag: heroTag,
        gallery: gallery,
      ).then(completer.complete),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewDialog), findsOneWidget);
  }

  ImageGalleryController galleryOf(
    List<MediaItem> items, {
    int initialIndex = 1,
    bool hasMore = false,
    Future<ImageGalleryPage> Function()? loadMore,
  }) {
    return ImageGalleryController(
      items: items,
      initialId: items[initialIndex].id,
      hasMore: hasMore,
      loadMore: loadMore,
    );
  }

  testWidgets('手机端按钮与键盘可切换上一张/下一张并更新序号', (tester) async {
    final items = galleryItems();
    final gallery = galleryOf(items);
    addTearDown(gallery.dispose);
    await openGallery(tester, items, gallery);

    expect(find.text('第 2 张'), findsOneWidget);
    expect(find.byTooltip('上一张'), findsOneWidget);
    expect(find.byTooltip('下一张'), findsOneWidget);

    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    expect(gallery.currentIndex, 2);
    expect(find.text('第 3 张'), findsOneWidget);
    // 已是最后一张，下一张按钮禁用且不回绕。
    final nextButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('下一张'),
        matching: find.byType(IconButton),
      ),
    );
    expect(nextButton.onPressed, isNull);
    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    expect(gallery.currentIndex, 2);

    await tester.tap(find.byTooltip('上一张'));
    await tester.pump();
    expect(gallery.currentIndex, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(gallery.currentIndex, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(gallery.currentIndex, 1);

    // Escape 关闭后无残留遮罩。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewDialog), findsNothing);
  });

  testWidgets('横向滑动切图；边界处滑动不回绕', (tester) async {
    final items = galleryItems();
    final gallery = galleryOf(items, initialIndex: 0);
    addTearDown(gallery.dispose);
    await openGallery(tester, items, gallery);

    // 首张向右滑不动作。
    await tester.fling(
      find.byType(ImagePreviewDialog),
      const Offset(300, 0),
      800,
    );
    await tester.pump();
    expect(gallery.currentIndex, 0);

    // 向左滑切下一张。
    await tester.fling(
      find.byType(ImagePreviewDialog),
      const Offset(-300, 0),
      800,
    );
    await tester.pump();
    expect(gallery.currentIndex, 1);
    expect(find.text('第 2 张'), findsOneWidget);
  });

  testWidgets('放大后单指拖动只平移不切图', (tester) async {
    final items = galleryItems();
    final gallery = galleryOf(items);
    addTearDown(gallery.dispose);
    await openGallery(tester, items, gallery);

    // 双击放大。
    final center = tester.getCenter(find.byType(ImagePreviewDialog));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(ImagePreviewDialog),
      const Offset(-300, 0),
      800,
    );
    await tester.pump();
    expect(gallery.currentIndex, 1, reason: '放大状态横向拖动应平移而非切图');
  });

  testWidgets('双指捏合不误触切图', (tester) async {
    final items = galleryItems();
    final gallery = galleryOf(items);
    addTearDown(gallery.dispose);
    await openGallery(tester, items, gallery);

    // 两指向外移动应放大当前图片，不得切图。
    final center = tester.getCenter(find.byType(ImagePreviewDialog));
    final first = await tester.createGesture(kind: PointerDeviceKind.touch);
    final second = await tester.createGesture(kind: PointerDeviceKind.touch);
    await first.down(center - const Offset(40, 0));
    await second.down(center + const Offset(40, 0));
    await first.moveBy(const Offset(-70, 0));
    await second.moveBy(const Offset(70, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(gallery.currentIndex, 1);
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      greaterThan(1),
    );
  });

  testWidgets('分页失败保留当前图并可重试成功', (tester) async {
    final items = galleryItems(count: 2);
    var attempts = 0;
    final gallery = ImageGalleryController(
      items: items,
      initialId: items[1].id,
      hasMore: true,
      loadMore: () async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('offline');
        }
        // 追加一页与初始条目不同 id 的图片，模拟远端分页。
        final extra = buildMediaFixtures()
            .where((entry) => entry.type == MediaType.image)
            .skip(2)
            .take(2)
            .toList();
        return ImageGalleryPage(items: extra, hasMore: false);
      },
    );
    addTearDown(gallery.dispose);
    await openGallery(tester, items, gallery);

    expect(find.text('第 2 张'), findsOneWidget);
    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    await tester.pump();
    // 失败后停留在原图并显示错误，不清空照片。
    expect(gallery.currentItem.id, items[1].id);
    expect(gallery.error, isNotNull);
    expect(find.text('加载失败，点下一张重试'), findsOneWidget);
    expect(find.byType(ImagePreviewDialog), findsOneWidget);

    // 重试成功后进入新页第一张。
    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    await tester.pump();
    expect(gallery.error, isNull);
    expect(gallery.currentItem.id, galleryItems()[2].id);
    expect(find.text('第 3 张'), findsOneWidget);
  });

  testWidgets('远端分页加载中关闭不留遮罩', (tester) async {
    final items = galleryItems(count: 2);
    final pending = Completer<ImageGalleryPage>();
    final gallery = ImageGalleryController(
      items: items,
      initialId: items.last.id,
      hasMore: true,
      loadMore: () => pending.future,
    );
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete(ImageGalleryPage(items: const [], hasMore: false));
      }
      gallery.dispose();
    });
    await openGallery(tester, items, gallery);

    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    await tester.pump();
    expect(gallery.isLoadingMore, isTrue);
    expect(find.text('正在加载更多…'), findsOneWidget);

    // 加载中直接关闭；迟到的分页完成不影响已关闭的预览。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewDialog), findsNothing);
    expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
  });

  testWidgets('画廊模式下详情动作回传 openDetails 并指向当前图', (tester) async {
    final items = galleryItems();
    final gallery = galleryOf(items);
    addTearDown(gallery.dispose);
    final result = Completer<ImagePreviewAction?>();
    await openGallery(tester, items, gallery, result: result);

    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    expect(gallery.currentItem.id, items[2].id);

    await tester.tap(find.byTooltip('详情'));
    await tester.pumpAndSettle();
    expect(await result.future, ImagePreviewAction.openDetails);
    // 调用方随后读取 gallery.currentItem，应得到切换后的图片。
    expect(gallery.currentItem.id, items[2].id);
  });

  testWidgets('切到其他图后关闭不做 Hero 回飞且桌面宽屏布局正常', (tester) async {
    final items = galleryItems();
    const heroTag = 'gallery-hero';
    final gallery = galleryOf(items);
    addTearDown(gallery.dispose);
    await openGallery(
      tester,
      items,
      gallery,
      surface: const Size(1280, 800),
      heroTag: heroTag,
    );

    // 打开态 Hero 存在；切换后图片不再携带来源标签。
    expect(find.byType(Hero), findsWidgets);
    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    expect(gallery.currentItem.id, items[2].id);
    expect(
      find.descendant(
        of: find.byType(ImagePreviewDialog),
        matching: find.byType(Hero),
      ),
      findsNothing,
    );

    // 宽屏下导航条与按钮依旧可达且无溢出。
    expect(find.byType(ImagePreviewNavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewDialog), findsNothing);
    expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(960, 640),
    const Size(1280, 800),
  ]) {
    for (final dark in [false, true]) {
      for (final dpi in [1.0, 1.25, 1.5]) {
        testWidgets('导航布局 $size dark=$dark dpi=$dpi 大字体', (tester) async {
          final items = galleryItems();
          final gallery = galleryOf(items);
          addTearDown(gallery.dispose);
          await openGallery(
            tester,
            items,
            gallery,
            surface: size,
            dark: dark,
            dpi: dpi,
            textScale: 1.5,
          );
          for (final label in ['上一张', '下一张', '关闭']) {
            final button = find.ancestor(
              of: find.byTooltip(label),
              matching: find.byType(IconButton),
            );
            final rect = tester.getRect(button);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(button.hitTestable(), findsOneWidget);
          }
          await tester.tap(find.byTooltip('上一张'));
          await tester.pump();
          expect(gallery.currentItem.id, items.first.id);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
