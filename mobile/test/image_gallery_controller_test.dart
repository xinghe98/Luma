// 图片库预览翻页会话的单元与组件集成测试：
// 覆盖排序顺序、两端边界、远程分页衔接、删除当前图后的落点与空会话、
// 迟到分页的删除过滤、失败重试与释放后的行为，
// 以及 LibraryPage 点击图片时交给预览的会话内容、首刷衔接和续页。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/app/app_navigation.dart';
import 'package:luma/app/app_route.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/shared/media/image_gallery_controller.dart';
import 'package:luma/shared/media/masonry_media_tile.dart';

void main() {
  group('ImageGalleryController', () {
    test('保持来源顺序并从选中项开始', () {
      final controller = ImageGalleryController(
        items: _items(5),
        initialId: 'img-2',
      );
      addTearDown(controller.dispose);

      expect(controller.currentIndex, 2);
      expect(controller.currentItem!.id, 'img-2');
      expect(controller.length, 5);
      expect(controller.canPrevious, isTrue);
      expect(controller.canNext, isTrue);
    });

    test('previous 到首张后不回绕', () {
      final controller = ImageGalleryController(
        items: _items(3),
        initialId: 'img-0',
      );
      addTearDown(controller.dispose);

      expect(controller.canPrevious, isFalse);
      controller.previous();
      expect(controller.currentIndex, 0);
    });

    test('翻页进行中 previous 被忽略', () async {
      final completer = Completer<ImageGalleryPage>();
      final controller = ImageGalleryController(
        items: _items(2),
        initialId: 'img-1',
        hasMore: true,
        loadMore: () => completer.future,
      );
      addTearDown(controller.dispose);

      final pending = controller.next();
      controller.previous();
      completer.complete(ImageGalleryPage(items: [_item(2)], hasMore: false));
      await pending;

      // previous 在进行中时被忽略，最终停在 next 落定的 img-2。
      expect(controller.currentItem!.id, 'img-2');
    });

    test('next 到末尾且无后续页时停下不回绕', () async {
      final controller = ImageGalleryController(
        items: _items(2),
        initialId: 'img-0',
      );
      addTearDown(controller.dispose);

      await controller.next();
      expect(controller.currentIndex, 1);
      expect(controller.canNext, isFalse);
      await controller.next();
      expect(controller.currentIndex, 1);
      expect(controller.currentItem!.id, 'img-1');
    });

    test('next 在末尾先拉取下一页再进入新页首项', () async {
      var loads = 0;
      final controller = ImageGalleryController(
        items: _items(2),
        initialId: 'img-1',
        hasMore: true,
        loadMore: () async {
          loads++;
          return ImageGalleryPage(items: [_item(2), _item(3)], hasMore: false);
        },
      );
      addTearDown(controller.dispose);

      await controller.next();
      expect(loads, 1);
      expect(controller.currentItem!.id, 'img-2');
      expect(controller.length, 4);
      expect(controller.canNext, isTrue);
    });

    test('进行中的 next 被串行化，重复调用只拉取一次', () async {
      var loads = 0;
      final completer = Completer<ImageGalleryPage>();
      final controller = ImageGalleryController(
        items: _items(1),
        initialId: 'img-0',
        hasMore: true,
        loadMore: () {
          loads++;
          return completer.future;
        },
      );
      addTearDown(controller.dispose);

      final first = controller.next();
      final second = controller.next();
      completer.complete(ImageGalleryPage(items: [_item(1)], hasMore: false));
      await Future.wait([first, second]);

      expect(loads, 1);
      expect(controller.currentItem!.id, 'img-1');
      expect(controller.isLoadingMore, isFalse);
    });

    test('拉取失败保留当前图片并允许重试', () async {
      var attempts = 0;
      final controller = ImageGalleryController(
        items: _items(1),
        initialId: 'img-0',
        hasMore: true,
        loadMore: () async {
          attempts++;
          if (attempts == 1) throw StateError('网络失败');
          return ImageGalleryPage(items: [_item(1)], hasMore: false);
        },
      );
      addTearDown(controller.dispose);

      await controller.next();
      expect(controller.currentItem!.id, 'img-0');
      expect(controller.error, isNotNull);
      expect(controller.isLoadingMore, isFalse);

      await controller.next();
      expect(attempts, 2);
      expect(controller.currentItem!.id, 'img-1');
      expect(controller.error, isNull);
    });

    test('新页按 id 去重追加且不改动已有顺序', () async {
      final controller = ImageGalleryController(
        items: _items(2),
        initialId: 'img-1',
        hasMore: true,
        loadMore: () async => ImageGalleryPage(
          // 模拟来源重排：已见过的 id 重新出现时被忽略。
          items: [_item(1), _item(2)],
          hasMore: false,
        ),
      );
      addTearDown(controller.dispose);

      await controller.next();
      expect(controller.length, 3);
      expect(controller.currentItem!.id, 'img-2');
    });

    test('dispose 之后忽略迟到的分页结果', () async {
      final completer = Completer<ImageGalleryPage>();
      final controller = ImageGalleryController(
        items: _items(1),
        initialId: 'img-0',
        hasMore: true,
        loadMore: () => completer.future,
      );

      final pending = controller.next();
      controller.dispose();
      completer.complete(ImageGalleryPage(items: [_item(1)], hasMore: false));
      await pending;

      expect(controller.currentItem!.id, 'img-0');
    });
    test('removeById 删除当前图后进入下一张', () async {
      final controller = ImageGalleryController(
        items: _items(3),
        initialId: 'img-1',
      );
      addTearDown(controller.dispose);

      expect(await controller.removeById(controller.currentItem!.id), isTrue);
      expect(controller.currentItem!.id, 'img-2');
      expect(controller.currentIndex, 1);
      expect(controller.length, 2);
    });

    test('removeById 删除最后一张后退回上一张', () async {
      final controller = ImageGalleryController(
        items: _items(3),
        initialId: 'img-2',
      );
      addTearDown(controller.dispose);

      expect(await controller.removeById(controller.currentItem!.id), isTrue);
      expect(controller.currentItem!.id, 'img-1');
      expect(controller.currentIndex, 1);
      expect(controller.canNext, isFalse);
    });

    test('removeById 删除唯一图片后会话变空', () async {
      final controller = ImageGalleryController(
        items: _items(1),
        initialId: 'img-0',
      );
      addTearDown(controller.dispose);

      expect(await controller.removeById(controller.currentItem!.id), isTrue);
      expect(controller.isEmpty, isTrue);
      expect(controller.currentItem, isNull);
    });

    test('removeById 删空已加载且来源还有后续页时补拉一页', () async {
      final controller = ImageGalleryController(
        items: _items(1),
        initialId: 'img-0',
        hasMore: true,
        loadMore: () async =>
            ImageGalleryPage(items: [_item(1), _item(2)], hasMore: false),
      );
      addTearDown(controller.dispose);

      expect(await controller.removeById(controller.currentItem!.id), isTrue);
      // 补拉后进入新页首项，不停留在已删除的 img-0 上。
      expect(controller.currentItem!.id, 'img-1');
      expect(controller.length, 2);
      expect(controller.isEmpty, isFalse);
    });

    test('删空后跳过只含已删图片的旧页，继续寻找有效图片', () async {
      var page = 0;
      final controller = ImageGalleryController(
        items: _items(1),
        initialId: 'img-0',
        hasMore: true,
        loadMore: () async => ++page == 1
            ? ImageGalleryPage(items: [_item(0)], hasMore: true)
            : ImageGalleryPage(items: [_item(1)], hasMore: false),
      );
      addTearDown(controller.dispose);
      await controller.removeById('img-0');
      expect(controller.currentItem!.id, 'img-1');
      expect(controller.containsId('img-0'), isFalse);
    });

    test('removeById 删空且补页失败时记录错误并保持空会话', () async {
      final controller = ImageGalleryController(
        items: _items(1),
        initialId: 'img-0',
        hasMore: true,
        loadMore: () async => throw StateError('网络失败'),
      );
      addTearDown(controller.dispose);

      expect(await controller.removeById(controller.currentItem!.id), isTrue);
      expect(controller.isEmpty, isTrue);
      expect(controller.currentItem, isNull);
      expect(controller.error, isNotNull);
    });

    test('isRemoved 过滤迟到分页里已删除的条目', () async {
      final removed = <String>{'img-2'};
      final controller = ImageGalleryController(
        items: _items(1),
        initialId: 'img-0',
        hasMore: true,
        isRemoved: removed.contains,
        loadMore: () async => ImageGalleryPage(
          // 模拟旧页回包里夹带已删除的图片。
          items: [_item(2), _item(3)],
          hasMore: false,
        ),
      );
      addTearDown(controller.dispose);

      await controller.next();
      expect(controller.length, 2);
      expect(controller.containsId('img-2'), isFalse);
      expect(controller.currentItem!.id, 'img-3');
    });

    test('removeById 在翻页进行中返回 false 不移除', () async {
      final completer = Completer<ImageGalleryPage>();
      final controller = ImageGalleryController(
        items: _items(2),
        initialId: 'img-1',
        hasMore: true,
        loadMore: () => completer.future,
      );
      addTearDown(() {
        if (!completer.isCompleted) {
          completer.complete(ImageGalleryPage(items: const [], hasMore: false));
        }
        controller.dispose();
      });

      final pending = controller.next();
      expect(await controller.removeById(controller.currentItem!.id), isFalse);
      completer.complete(ImageGalleryPage(items: [_item(2)], hasMore: false));
      await pending;
      // 翻页正常落定，删除请求未偷偷生效。
      expect(controller.currentItem!.id, 'img-2');
      expect(controller.length, 3);
    });

    test('removeById 移除非当前项时当前图片不变索引前移', () async {
      final controller = ImageGalleryController(
        items: _items(3),
        initialId: 'img-2',
      );
      addTearDown(controller.dispose);

      // 删除当前项之前的条目：当前图不变，索引随之前移。
      expect(await controller.removeById('img-0'), isTrue);
      expect(controller.currentItem!.id, 'img-2');
      expect(controller.currentIndex, 1);
      expect(controller.length, 2);
    });

    test('removeById 移除不存在的 id 返回 false', () async {
      final controller = ImageGalleryController(
        items: _items(2),
        initialId: 'img-0',
      );
      addTearDown(controller.dispose);

      expect(await controller.removeById('missing'), isFalse);
      expect(controller.length, 2);
      expect(controller.currentItem!.id, 'img-0');
    });
  });

  group('LibraryPage 图片库预览会话', () {
    Future<ImageGalleryController> pumpLibraryAndOpen(
      WidgetTester tester,
      MockMediaRepository repository, {
      List<MediaItem> initialItems = const [],
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dependencies = AppDependencies(
        mediaRepository: repository,
        catalogRepository: const EmptyCatalogRepository(),
        connectionService: MockConnectionService(),
      );
      final opened = Completer<ImageGalleryController>();
      final previewOpen = Completer<void>();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (!previewOpen.isCompleted) previewOpen.complete();
        dependencies.dispose();
      });
      await tester.pumpWidget(
        AppScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: LumaTheme.light(),
            home: LibraryPage(
              type: MediaType.image,
              pageSize: 18,
              initialItems: initialItems,
              onOpenMedia: (_, {heroTag}) {},
              onOpenImageGallery: (gallery, {heroTag}) {
                opened.complete(gallery);
                return previewOpen.future;
              },
              onOpenSearch: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (
        var frame = 0;
        frame < 20 && find.byType(MasonryMediaTile).evaluate().isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(MasonryMediaTile), findsWidgets);
      await tester.tap(find.byType(MasonryMediaTile).first);
      await tester.pump();
      return opened.future;
    }

    testWidgets('点击图片后沿同一游标续页且保持来源顺序', (tester) async {
      final repository = _PagedImageRepository(total: 40, pageSize: 18);
      final gallery = await pumpLibraryAndOpen(tester, repository);
      expect(gallery.length, 18);
      expect(gallery.currentItem!.id, 'img-0');
      for (var i = 0; i < 17; i++) {
        await gallery.next();
      }
      expect(gallery.currentItem!.id, 'img-17');
      await gallery.next();
      expect(gallery.currentItem!.id, 'img-18');
      expect(gallery.length, 36);
      expect(repository.cursors, [null, '18']);
    });

    testWidgets('来源分页失败后保留图片并允许显式重试', (tester) async {
      final repository = _PagedImageRepository(
        total: 40,
        pageSize: 18,
        failOnCursor: '18',
      );
      final gallery = await pumpLibraryAndOpen(tester, repository);
      for (var i = 0; i < 17; i++) {
        await gallery.next();
      }
      await gallery.next();
      expect(gallery.currentItem!.id, 'img-17');
      expect(gallery.error, isNotNull);
      repository.failOnCursor = null;
      await gallery.next();
      expect(gallery.currentItem!.id, 'img-18');
      expect(gallery.error, isNull);
      expect(repository.cursors, [null, '18', '18']);
    });

    testWidgets('从首帧种子打开后衔接在途首页，不跳过未见图片', (tester) async {
      final gate = Completer<void>();
      final repository = _PagedImageRepository(
        total: 40,
        pageSize: 18,
        firstPageGate: gate,
      );
      final gallery = await pumpLibraryAndOpen(
        tester,
        repository,
        initialItems: _items(3),
      );
      await gallery.next();
      await gallery.next();
      final pending = gallery.next();
      expect(gallery.currentItem!.id, 'img-2');
      expect(gallery.isLoadingMore, isTrue);
      gate.complete();
      await tester.pump();
      await pending;
      expect(gallery.currentItem!.id, 'img-3');
      expect(gallery.length, 18);
      expect(repository.cursors, [null]);
    });

    testWidgets('首刷失败后预览可重试，不把种子误认为全部图片', (tester) async {
      final gate = Completer<void>();
      final repository = _PagedImageRepository(
        total: 40,
        pageSize: 18,
        firstPageGate: gate,
        failFirstPage: true,
      );
      final gallery = await pumpLibraryAndOpen(
        tester,
        repository,
        initialItems: _items(1),
      );
      gate.complete();
      await tester.pump();
      await gallery.next();
      expect(gallery.currentItem!.id, 'img-0');
      expect(gallery.error, isNotNull);
      expect(gallery.canNext, isTrue);
      repository.failFirstPage = false;
      await gallery.next();
      expect(gallery.currentItem!.id, 'img-1');
      expect(gallery.error, isNull);
    });

    testWidgets('来源页面销毁会唤醒等待中的续页', (tester) async {
      final gate = Completer<void>();
      final repository = _PagedImageRepository(
        total: 40,
        pageSize: 18,
        firstPageGate: gate,
      );
      final gallery = await pumpLibraryAndOpen(
        tester,
        repository,
        initialItems: _items(1),
      );
      final pending = gallery.next();
      expect(gallery.isLoadingMore, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await pending;
      expect(gallery.currentItem!.id, 'img-0');
      expect(gallery.canNext, isFalse);
      gate.complete();
      await tester.pump();
    });
  });
  testWidgets('预览切图后详情路由使用当前图片与首帧模型', (tester) async {
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: MockConnectionService(),
    );
    final gallery = ImageGalleryController(
      items: _items(2),
      initialId: 'img-0',
    );
    String? detailId;
    MediaDetailRouteData? detailData;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.openImagePreview(
                gallery.currentItem!,
                gallery: gallery,
              ),
              child: const Text('打开预览'),
            ),
          ),
        ),
        GoRoute(
          name: AppRoute.mediaDetail,
          path: '/media/:mediaId',
          builder: (_, state) {
            detailId = state.pathParameters['mediaId'];
            detailData = state.extra! as MediaDetailRouteData;
            return const Scaffold(body: Text('图片详情页'));
          },
        ),
      ],
    );
    try {
      await tester.pumpWidget(
        AppScope(
          dependencies: dependencies,
          child: MaterialApp.router(
            theme: LumaTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开预览'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一张'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('详情'));
      await tester.pumpAndSettle();
      expect(detailId, 'img-1');
      expect(detailData!.initialItem!.id, 'img-1');
      expect(find.text('图片详情页'), findsOneWidget);
      expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      gallery.dispose();
      dependencies.dispose();
    }
  });
}

MediaItem _item(int index) => MediaItem(
  id: 'img-$index',
  title: '图片 $index',
  type: MediaType.image,
  duration: Duration.zero,
  resolution: '4000x3000',
  format: 'JPG',
  fileSize: '2.0 MB',
  directory: '/photos',
  tags: const [],
  addedAt: DateTime(2026, 8, 1).subtract(Duration(days: index)),
  artSeed: index,
  aspectRatio: 0.5,
);

List<MediaItem> _items(int count) => [for (var i = 0; i < count; i++) _item(i)];

/// 按服务端游标分页的图片仓库，记录每次请求的游标供断言。
class _PagedImageRepository extends MockMediaRepository {
  _PagedImageRepository({
    required this.total,
    required this.pageSize,
    this.failOnCursor,
    this.firstPageGate,
    this.failFirstPage = false,
  });

  final int total;
  final int pageSize;

  /// 命中该游标时令请求失败一次；置空后恢复。
  String? failOnCursor;
  bool failFirstPage;

  /// 非空时首页（cursor==null）请求先等该闸门，用于模拟打开时的在途首刷。
  final Completer<void>? firstPageGate;

  final cursors = <String?>[];

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async {
    cursors.add(cursor);
    if (cursor == null && firstPageGate != null) {
      await firstPageGate!.future;
    }
    if (cursor == null && failFirstPage) throw StateError('首页请求失败');
    if (failOnCursor != null && cursor == failOnCursor) {
      throw StateError('分页请求失败');
    }
    final size = limit ?? pageSize;
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + size).clamp(0, total);
    final items = [for (var i = start; i < end; i++) _item(i)];
    return MediaListPage(items: items, nextCursor: end < total ? '$end' : null);
  }
}
