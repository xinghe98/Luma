// 首页与货架回归：覆盖异步媒体通知、刷新后的焦点身份及真实缩略图解码。
// 复用 AppDependencies、控制器和卡片；仓库延迟由测试释放，组件卸载后统一销毁依赖与图片缓存。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/core/theme/tv_theme.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_page.dart';
import 'package:luma/features/catalog/widgets/catalog_card.dart';
import 'package:luma/features/home/home_page.dart';
import 'package:luma/features/home/widgets/horizontal_media_section.dart';
import 'package:luma/shared/interaction/luma_focusable_surface.dart';
import 'package:luma/shared/interaction/tv_key_bindings.dart';
import 'package:luma/shared/media/media_card.dart';
import 'package:luma/shared/media/responsive_media_grid.dart';
import 'package:luma/shared/states/skeleton.dart';

const _layouts = [
  (name: 'phone light', size: Size(430, 932), tv: false, dark: false),
  (name: 'wide dark', size: Size(1440, 1080), tv: false, dark: true),
  (name: 'TV dark', size: Size(1920, 1080), tv: true, dark: true),
];

MediaItem _media(String id, {double progress = 0}) => MediaItem(
  id: id,
  title: '视频 $id',
  type: MediaType.video,
  duration: const Duration(seconds: 100),
  resolution: '1080p',
  format: 'mp4',
  fileSize: '1 MB',
  directory: '/',
  tags: const [],
  addedAt: DateTime(2026),
  artSeed: 0,
  aspectRatio: 1.6,
  progress: progress,
);

CatalogItem _catalog(String id) => CatalogItem(
  id: id,
  sourceId: 'source',
  kind: CatalogKind.movie,
  title: '电影 $id',
  year: 2026,
  mediaCount: 1,
  episodeCount: 0,
  completedCount: 0,
  playableMediaId: 'media-$id',
  thumbnailUrl: '',
  posterUrl: '',
  durationMs: 100000,
  resolution: '1080p',
  progressMs: 0,
  completed: false,
  updatedAt: DateTime(2026),
);

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

AppDependencies _dependencies({
  _FeedRepository? media,
  _CatalogRepository? catalog,
  bool tv = false,
  ApiSession? session,
}) {
  final dependencies = AppDependencies(
    mediaRepository: media ?? _FeedRepository(),
    catalogRepository: catalog,
    connectionService: MockConnectionService(),
    deviceProfile: tv ? AppDeviceProfile.television : AppDeviceProfile.standard,
    apiSession: session,
  );
  addTearDown(dependencies.dispose);
  return dependencies;
}

Widget _app(
  AppDependencies dependencies,
  Widget child, {
  bool dark = false,
  double textScale = 1.25,
}) {
  final theme = dark ? LumaTheme.dark() : LumaTheme.light();
  return AppScope(
    dependencies: dependencies,
    child: MaterialApp(
      theme: dependencies.deviceProfile.isTelevision
          ? applyTvTheme(theme)
          : theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: TvKeyBindings(child: child!),
      ),
      home: child,
    ),
  );
}

Finder _mediaCard(String id) => find.byWidgetPredicate(
  (widget) => widget is MediaCard && widget.item.id == id,
);

Finder _catalogCard(String id) => find.byWidgetPredicate(
  (widget) => widget is CatalogCard && widget.item.id == id,
);

Finder _surface(Finder card) =>
    find.descendant(of: card, matching: find.byType(LumaFocusableSurface));

InkWell _ink(WidgetTester tester, Finder card) => tester.widget<InkWell>(
  find.descendant(of: _surface(card), matching: find.byType(InkWell)).first,
);

Future<FocusNode> _focus(WidgetTester tester, Finder card) async {
  await tester.ensureVisible(card);
  final node = _ink(tester, card).focusNode!;
  node.requestFocus();
  await tester.pumpAndSettle();
  _expectFocus(tester, card);
  return node;
}

void _expectFocus(WidgetTester tester, Finder card) {
  expect(_ink(tester, card).focusNode!.hasFocus, isTrue);
  final decoration =
      tester
              .widget<AnimatedContainer>(
                find
                    .descendant(
                      of: _surface(card),
                      matching: find.byType(AnimatedContainer),
                    )
                    .first,
              )
              .foregroundDecoration!
          as BoxDecoration;
  expect(decoration.border!.top.width, LumaTvLayout.focusStroke);
}

void _expectCardContentFits(WidgetTester tester) {
  for (final element in find.byType(MediaCard).evaluate()) {
    final card = find.byWidget(element.widget);
    final bounds = tester.getRect(card);
    final contents = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) => widget is Text || widget is LinearProgressIndicator,
      ),
    );
    for (final content in contents.evaluate()) {
      final rect = tester.getRect(find.byWidget(content.widget));
      expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.01));
      expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.01));
    }
  }
}

Future<void> _select(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pump();
}

Future<void> _homeRefresh(WidgetTester tester, {required bool tv}) async {
  if (tv) {
    await tester.tap(find.byTooltip('刷新媒体库'));
  } else {
    await tester.dragFrom(
      tester.getTopLeft(find.byType(CustomScrollView).first) +
          const Offset(30, 80),
      const Offset(0, 700),
    );
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final layout in _layouts) {
    testWidgets(
      '${layout.name}: delayed home load replaces skeleton with usable card',
      (tester) async {
        _viewport(tester, layout.size);
        final repository = _FeedRepository();
        repository.pendingLoad = Completer<List<MediaItem>>();
        final dependencies = _dependencies(media: repository, tv: layout.tv);
        final loading = dependencies.media.load();
        String? opened;
        await tester.pumpWidget(
          _app(
            dependencies,
            HomePage(
              onOpenMedia: (item, {heroTag}) => opened = item.id,
              onOpenSearch: () {},
            ),
            dark: layout.dark,
          ),
        );
        expect(find.byType(HomeFeedSkeleton), findsOneWidget);
        repository.items = [_media('loaded')];
        repository.pendingLoad!.complete(repository.items);
        await loading;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(HomeFeedSkeleton), findsNothing);
        expect(_mediaCard('loaded'), findsOneWidget);
        await tester.tap(_mediaCard('loaded'));
        expect(opened, 'loaded');
        if (layout.tv) {
          opened = null;
          await _focus(tester, _mediaCard('loaded'));
          await _select(tester);
          expect(opened, 'loaded');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${layout.name}: refresh failure and retry replace visible feed',
      (tester) async {
        _viewport(tester, layout.size);
        final repository = _FeedRepository()..items = [_media('old')];
        final dependencies = _dependencies(media: repository, tv: layout.tv);
        await dependencies.media.load();
        await tester.pumpWidget(
          _app(
            dependencies,
            HomePage(onOpenMedia: (_, {heroTag}) {}, onOpenSearch: () {}),
            dark: layout.dark,
          ),
        );
        await tester.pumpAndSettle();
        repository.pendingRefresh = Completer<List<MediaItem>>();
        await _homeRefresh(tester, tv: layout.tv);
        expect(repository.refreshCalls, 1);
        expect(_mediaCard('old'), findsOneWidget);
        repository.pendingRefresh!.completeError(
          StateError('refresh unavailable'),
        );
        await tester.pumpAndSettle();
        expect(find.text('首页刷新失败'), findsOneWidget);
        expect(_mediaCard('old'), findsOneWidget);
        repository.pendingRefresh = Completer<List<MediaItem>>();
        await tester.tap(find.byTooltip('重试刷新'));
        await tester.pump();
        expect(repository.refreshCalls, 2);
        repository.items = [_media('new')];
        repository.pendingRefresh!.complete(repository.items);
        await tester.pumpAndSettle();
        expect(find.text('首页刷新失败'), findsNothing);
        expect(_mediaCard('old'), findsNothing);
        expect(_mediaCard('new'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('${layout.name}: playback update redraws home progress', (
      tester,
    ) async {
      _viewport(tester, layout.size);
      final repository = _FeedRepository()
        ..items = [_media('playing', progress: 0.25)];
      final dependencies = _dependencies(media: repository, tv: layout.tv);
      await dependencies.media.load();
      await tester.pumpWidget(
        _app(
          dependencies,
          HomePage(onOpenMedia: (_, {heroTag}) {}, onOpenSearch: () {}),
          dark: layout.dark,
        ),
      );
      await tester.pumpAndSettle();
      Finder progress() => find.descendant(
        of: _mediaCard('playing').first,
        matching: find.byType(LinearProgressIndicator),
      );
      expect(tester.widget<LinearProgressIndicator>(progress()).value, 0.25);
      await dependencies.media.updateProgress('playing', 50000);
      await tester.pumpAndSettle();
      expect(tester.widget<LinearProgressIndicator>(progress()).value, 0.5);
      _expectCardContentFits(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      '${layout.name}: favorite mutation redraws home favorite shelf',
      (tester) async {
        _viewport(tester, layout.size);
        final repository = _FeedRepository()..items = [_media('favorite')];
        final dependencies = _dependencies(media: repository, tv: layout.tv);
        await dependencies.media.load();
        String? opened;
        await tester.pumpWidget(
          _app(
            dependencies,
            HomePage(
              onOpenMedia: (item, {heroTag}) => opened = item.id,
              onOpenSearch: () {},
            ),
            dark: layout.dark,
          ),
        );
        await tester.pumpAndSettle();
        if (layout.tv) {
          // TV 收藏由详情写回同一媒体控制器，首页不提供覆盖式收藏按钮。
          await dependencies.media.toggleFavorite('favorite');
        } else {
          await tester.tap(find.byTooltip('收藏').first);
        }
        await tester.pumpAndSettle();
        final shelf = find.byWidgetPredicate(
          (widget) => widget is HorizontalMediaSection && widget.title == '收藏',
        );
        final favoriteCard = find.descendant(
          of: shelf,
          matching: _mediaCard('favorite'),
        );
        await tester.scrollUntilVisible(
          favoriteCard,
          250,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
        expect(
          find.descendant(of: shelf, matching: find.text('视频 favorite')),
          findsOneWidget,
        );
        final favoriteTitle = find.descendant(
          of: favoriteCard,
          matching: find.text('视频 favorite'),
        );
        await tester.ensureVisible(favoriteTitle);
        await tester.pumpAndSettle();
        _expectCardContentFits(tester);
        expect(favoriteTitle.hitTestable(), findsOneWidget);
        await tester.tap(favoriteTitle);
        expect(opened, 'favorite');
        if (layout.tv) {
          opened = null;
          await _focus(tester, favoriteCard);
          await _select(tester);
          expect(opened, 'favorite');
        } else {
          expect(
            find.descendant(of: favoriteCard, matching: find.byTooltip('取消收藏')),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final layout in _layouts.where((layout) => !layout.tv)) {
    for (final sliver in [false, true]) {
      testWidgets(
        '${layout.name}: ${sliver ? 'sliver' : 'box'} grid keeps scaled title footer and progress inside card',
        (tester) async {
          _viewport(tester, layout.size);
          final dependencies = _dependencies();
          final item = _media(
            'scaled',
            progress: 0.5,
          ).copyWith(title: '一段需要显示两行的影片标题 A longer video title');
          String? opened;
          void open(MediaItem item, {String? heroTag}) => opened = item.id;
          await tester.pumpWidget(
            _app(
              dependencies,
              Scaffold(
                body: sliver
                    ? CustomScrollView(
                        slivers: [
                          ResponsiveMediaSliverGrid(items: [item], onTap: open),
                        ],
                      )
                    : ResponsiveMediaGrid(items: [item], onTap: open),
              ),
              dark: layout.dark,
              textScale: 1.5,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(item.title), findsOneWidget);
          final progress = find.descendant(
            of: _mediaCard(item.id),
            matching: find.byType(LinearProgressIndicator),
          );
          expect(tester.widget<LinearProgressIndicator>(progress).value, 0.5);
          _expectCardContentFits(tester);
          await tester.tap(find.text(item.title));
          expect(opened, item.id);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'TV media shelf reorder preserves focused B and Right opens new neighbor A',
    (tester) async {
      _viewport(tester, const Size(1920, 1080));
      final dependencies = _dependencies(tv: true);
      final items = ValueNotifier([_media('A'), _media('B'), _media('C')]);
      addTearDown(items.dispose);
      final opened = <String>[];
      await tester.pumpWidget(
        _app(
          dependencies,
          Scaffold(
            body: ValueListenableBuilder<List<MediaItem>>(
              valueListenable: items,
              builder: (context, value, _) => HorizontalMediaSection(
                title: '继续观看',
                subtitle: '货架',
                heroPrefix: 'feed',
                items: value,
                onOpenMedia: (item, {heroTag}) => opened.add(item.id),
                onFavorite: (_) {},
              ),
            ),
          ),
          dark: true,
        ),
      );
      final node = await _focus(tester, _mediaCard('B'));
      await _select(tester);
      expect(opened, ['B']);
      items.value = [_media('B'), _media('A'), _media('C')];
      await tester.pumpAndSettle();
      _expectFocus(tester, _mediaCard('B'));
      expect(_ink(tester, _mediaCard('B')).focusNode, same(node));
      await _select(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      _expectFocus(tester, _mediaCard('A'));
      await _select(tester);
      expect(opened, ['B', 'B', 'A']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'TV catalog shelf removal preserves focused B and Right opens C',
    (tester) async {
      _viewport(tester, const Size(1920, 1080));
      final repository = _CatalogRepository()
        ..items = ['A', 'B', 'C', 'D'].map(_catalog).toList();
      final dependencies = _dependencies(catalog: repository, tv: true);
      final opened = <String>[];
      await tester.pumpWidget(
        _app(
          dependencies,
          CatalogPage(
            onOpenCatalog: (item, {heroTag}) => opened.add(item.id),
            onOpenPersonalMedia: (_, {heroTag}) {},
            onOpenSearch: () {},
            onOpenMovies: (_) {},
            onOpenSeries: (_) {},
            onOpenPersonalVideos: (_) {},
          ),
          dark: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final node = await _focus(tester, _catalogCard('B'));
      repository.pending = Completer<List<CatalogItem>>();
      dependencies.catalog.invalidate('B');
      await tester.pump();
      repository.items = ['B', 'C', 'D'].map(_catalog).toList();
      repository.pending!.complete(repository.items);
      await tester.pumpAndSettle();
      _expectFocus(tester, _catalogCard('B'));
      expect(_ink(tester, _catalogCard('B')).focusNode, same(node));
      await _select(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      _expectFocus(tester, _catalogCard('C'));
      await _select(tester);
      expect(opened, ['B', 'C']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'TV catalog grid delayed insertion preserves focused B and Right opens C',
    (tester) async {
      _viewport(tester, const Size(1920, 1080));
      final repository = _CatalogRepository()
        ..pending = Completer<List<CatalogItem>>();
      final dependencies = _dependencies(catalog: repository, tv: true);
      final opened = <String>[];
      await tester.pumpWidget(
        _app(
          dependencies,
          CatalogCollectionPage(
            kind: CatalogKind.movie,
            initialItems: ['A', 'B', 'C', 'D'].map(_catalog).toList(),
            onOpenCatalog: (item, {heroTag}) => opened.add(item.id),
            onOpenSearch: () {},
          ),
          dark: true,
        ),
      );
      // 初次请求保持在途，加载条持续动画期间只推进有限帧。
      await tester.pump(const Duration(milliseconds: 400));
      final card = _catalogCard('B');
      final node = _ink(tester, card).focusNode!;
      node.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      _expectFocus(tester, card);
      repository.items = ['X', 'A', 'B', 'C', 'D'].map(_catalog).toList();
      repository.pending!.complete(repository.items);
      await tester.pumpAndSettle();
      _expectFocus(tester, _catalogCard('B'));
      expect(_ink(tester, _catalogCard('B')).focusNode, same(node));
      await _select(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      _expectFocus(tester, _catalogCard('C'));
      await _select(tester);
      expect(opened, ['B', 'C']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'non-Hero video cards decode a 16:10 thumbnail without distortion on phone wide and TV',
    (tester) async {
      _viewport(tester, const Size(1920, 1080));
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      final bytes = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 640, 400),
          Paint()..color = Colors.blue,
        );
        canvas.drawCircle(
          const Offset(320, 200),
          100,
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording();
        final image = await picture
            .toImage(640, 400)
            .timeout(const Duration(seconds: 10));
        final data = await image
            .toByteData(format: ui.ImageByteFormat.png)
            .timeout(const Duration(seconds: 10));
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      }))!;
      final client = _ImageClient(bytes);
      await HttpOverrides.runZoned(() async {
        for (final configuration in [
          (width: 208.0, tv: false, dark: false),
          (width: 320.0, tv: false, dark: true),
          (width: 280.0, tv: true, dark: true),
        ]) {
          final dependencies = _dependencies(
            tv: configuration.tv,
            session: ApiSession(origin: 'https://thumbnail.test'),
          );
          await tester.pumpWidget(
            _app(
              dependencies,
              Scaffold(
                body: Center(
                  child: SizedBox(
                    width: configuration.width,
                    child: MediaCard(
                      item: _media(
                        'thumbnail',
                      ).copyWith(cardThumbnailUrl: '/thumbnail.png'),
                      onTap: () {},
                    ),
                  ),
                ),
              ),
              dark: configuration.dark,
            ),
          );
          final imageWidget = tester.widget<Image>(find.byType(Image));
          await tester.runAsync(() async {
            final loaded = Completer<void>();
            final stream = imageWidget.image.resolve(ImageConfiguration.empty);
            late ImageStreamListener listener;
            listener = ImageStreamListener(
              (info, _) {
                info.dispose();
                if (!loaded.isCompleted) loaded.complete();
              },
              onError: (Object error, StackTrace? stack) {
                if (!loaded.isCompleted) loaded.completeError(error, stack);
              },
            );
            stream.addListener(listener);
            try {
              await loaded.future.timeout(const Duration(seconds: 10));
            } finally {
              stream.removeListener(listener);
            }
          });
          await tester.pumpAndSettle();
          final raw = tester.widget<RawImage>(find.byType(RawImage));
          final decoded = raw.image!;
          expect(decoded.width / decoded.height, closeTo(1.6, 0.01));
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }, createHttpClient: (_) => client);
    },
  );
}

class _FeedRepository extends MockMediaRepository {
  List<MediaItem> items = [];
  Completer<List<MediaItem>>? pendingLoad;
  Completer<List<MediaItem>>? pendingRefresh;
  int refreshCalls = 0;

  @override
  Future<List<MediaItem>> loadMedia() async =>
      pendingLoad == null ? items : await pendingLoad!.future;

  @override
  Future<List<MediaItem>> refresh() async {
    refreshCalls++;
    return pendingRefresh == null ? items : await pendingRefresh!.future;
  }

  @override
  Future<List<MediaItem>> loadContinueWatching() async =>
      items.where((item) => item.watchStatus == WatchStatus.watching).toList();

  @override
  Future<int> countMedia({MediaType? type}) async => items.length;

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async => const MediaListPage(items: [], nextCursor: null);

  @override
  Future<MediaItem> setFavorite(String id, bool value) async =>
      _replace(id, (item) => item.copyWith(isFavorite: value));

  @override
  Future<MediaItem> updateProgress(String id, int positionMs) async => _replace(
    id,
    (item) =>
        item.copyWith(progress: positionMs / item.duration.inMilliseconds),
  );

  MediaItem _replace(String id, MediaItem Function(MediaItem) update) {
    final index = items.indexWhere((item) => item.id == id);
    final item = update(items[index]);
    items = [...items]..[index] = item;
    return item;
  }
}

class _CatalogRepository implements CatalogRepository {
  List<CatalogItem> items = [];
  Completer<List<CatalogItem>>? pending;

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async =>
      kind == CatalogKind.series
      ? []
      : pending == null
      ? items
      : await pending!.future;

  @override
  Future<CatalogItem> detail(String id) async =>
      items.firstWhere((item) => item.id == id);

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async => CatalogFavorite(favorite: favorite, revision: revision + 1);
}

// 只替换 HTTP 传输，NetworkImage 与 Flutter 解码器仍处理真实 PNG 数据。
class _ImageClient implements HttpClient {
  _ImageClient(this.bytes);
  final Uint8List bytes;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest implements HttpClientRequest {
  _ImageRequest(this.bytes);
  final Uint8List bytes;

  @override
  HttpHeaders get headers => _ImageHeaders();

  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  _ImageResponse(this.bytes);
  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
