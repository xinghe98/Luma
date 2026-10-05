// 详情返回回归使用真实 go_router、影视库与完整列表，验证来源路由、滚动和焦点。
// 内存仓储控制正常、加载及失败状态；每例卸载页面后释放路由与依赖。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_router.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/core/theme/tv_theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_detail_page.dart';
import 'package:luma/features/catalog/catalog_page.dart';
import 'package:luma/features/catalog/widgets/catalog_card.dart';
import 'package:luma/features/details/media_detail_page.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/shared/layout/section_header.dart';
import 'package:luma/shared/media/media_card.dart';

const _viewports = [
  (name: '手机', size: Size(390, 844), television: false),
  (name: 'Windows', size: Size(1280, 800), television: false),
  (name: 'TV', size: Size(1280, 720), television: true),
];

enum _Back { button, system, escape }

enum _DetailState { ready, loading, error }

void main() {
  for (final viewport in _viewports) {
    for (final kind in CatalogKind.values) {
      for (final collection in [false, true]) {
        for (final back in _Back.values) {
          testWidgets(
            '${viewport.name} ${kind.name} ${collection ? '查看全部' : '影视库'} '
            '${back.name} 返回保留来源焦点与滚动',
            (tester) async {
              final harness = await _mount(
                tester,
                size: viewport.size,
                television: viewport.television,
                detailState: back == _Back.button
                    ? _DetailState.error
                    : _DetailState.ready,
              );
              final heading = kind == CatalogKind.movie ? '电影' : '电视剧';
              await _showSection(tester, heading);
              if (collection) {
                await _openAll(tester, heading);
              }
              final source = find.byType(
                collection ? CatalogCollectionPage : CatalogPage,
              );
              final sourceState = tester.state(source);
              final scroll = _scroll(tester, source);
              if (collection) {
                scroll.jumpTo(500);
                await tester.pumpAndSettle();
              } else if (kind == CatalogKind.movie) {
                scroll.jumpTo(48);
                await tester.pumpAndSettle();
              }
              final card = find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is CatalogCard && widget.item.kind == kind,
                  )
                  .hitTestable()
                  .first;
              final item = tester.widget<CatalogCard>(card).item;
              final focus = await _focusCard(tester, card);
              final offset = scroll.offset;
              expect(offset, greaterThan(0));
              if (back == _Back.button) {
                await tester.tap(card);
              } else {
                await tester.sendKeyEvent(
                  viewport.television
                      ? LogicalKeyboardKey.select
                      : LogicalKeyboardKey.enter,
                );
              }
              await tester.pumpAndSettle();
              expect(find.byType(CatalogDetailPage), findsOneWidget);
              expect(_location(harness.router), '/catalog/${item.id}');
              if (viewport.television) {
                final playText = find
                    .descendant(
                      of: find.byType(FilledButton),
                      matching: find.byType(Text),
                    )
                    .first;
                expect(
                  Focus.of(tester.element(playText)).hasPrimaryFocus,
                  isTrue,
                );
              }
              if (back == _Back.button) {
                expect(find.text('作品资料刷新失败，当前仍显示上次内容。'), findsOneWidget);
              }
              await _back(tester, back, catalog: true);
              expect(
                _location(harness.router),
                collection
                    ? '/videos/${kind == CatalogKind.movie ? 'movies' : 'series'}'
                    : '/videos',
              );
              expect(tester.state(source), same(sourceState));
              expect(scroll.offset, closeTo(offset, 0.5));
              expect(focus.hasPrimaryFocus, isTrue);
              expect(find.byType(CatalogDetailPage), findsNothing);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            },
          );
        }
      }
    }

    for (final collection in [false, true]) {
      for (final back in _Back.values) {
        testWidgets('${viewport.name} 个人视频${collection ? '查看全部' : '影视库'} '
            '${back.name} 返回保留来源', (tester) async {
          final harness = await _mount(
            tester,
            size: viewport.size,
            television: viewport.television,
            detailState: back == _Back.button
                ? _DetailState.error
                : _DetailState.ready,
          );
          await _showSection(tester, '个人视频');
          if (collection) await _openAll(tester, '个人视频');
          final source = find.byType(collection ? LibraryPage : CatalogPage);
          final sourceState = tester.state(source);
          final scroll = _scroll(tester, source);
          if (collection) {
            scroll.jumpTo(500);
            await tester.pumpAndSettle();
          }
          final card = find.byType(MediaCard).hitTestable().first;
          final item = tester.widget<MediaCard>(card).item;
          final focus = await _focusCard(tester, card);
          final offset = scroll.offset;
          if (back == _Back.button) {
            await tester.tap(card);
          } else {
            await tester.sendKeyEvent(
              viewport.television
                  ? LogicalKeyboardKey.select
                  : LogicalKeyboardKey.enter,
            );
          }
          await tester.pumpAndSettle();
          expect(find.byType(MediaDetailPage), findsOneWidget);
          expect(_location(harness.router), '/media/${item.id}');
          if (viewport.television) {
            expect(
              FocusManager.instance.primaryFocus?.debugLabel,
              'media-detail-play',
            );
          }
          await _back(tester, back, catalog: false);
          expect(
            _location(harness.router),
            collection ? '/videos/personal' : '/videos',
          );
          expect(tester.state(source), same(sourceState));
          expect(scroll.offset, closeTo(offset, 0.5));
          expect(focus.hasPrimaryFocus, isTrue);
          expect(find.byType(MediaDetailPage), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }

    for (final catalog in [true, false]) {
      for (final (back, state) in const [
        (_Back.button, _DetailState.loading),
        (_Back.button, _DetailState.error),
        (_Back.system, _DetailState.error),
        (_Back.escape, _DetailState.ready),
        (_Back.escape, _DetailState.loading),
      ]) {
        testWidgets('${viewport.name} ${catalog ? '作品' : '媒体'}深链 ${state.name} '
            '${back.name} 无来源时回首页', (tester) async {
          final harness = await _mount(
            tester,
            size: viewport.size,
            television: viewport.television,
            initialLocation: catalog ? '/catalog/movie-0' : '/media/personal-0',
            detailState: state,
            settle: state != _DetailState.loading,
          );
          expect(harness.router.canPop(), isFalse);
          await _back(tester, back, catalog: catalog);
          expect(_location(harness.router), '/home');
          expect(find.byType(CatalogDetailPage), findsNothing);
          expect(find.byType(MediaDetailPage), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('TV 遥控返回长按只退出当前详情，按键不穿透到来源列表', (tester) async {
    final harness = await _mount(
      tester,
      size: const Size(1280, 720),
      television: true,
    );
    await _openAll(tester, '电影');
    final card = find.byType(CatalogCard).hitTestable().first;
    await _focusCard(tester, card);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    // Flutter 测试没有 GoBack 的默认物理键映射，长按三阶段必须使用同一键码。
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.sendKeyRepeatEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
    await tester.pumpAndSettle();
    expect(_location(harness.router), '/videos/movies');
    expect(find.byType(CatalogCollectionPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final catalog in [true, false]) {
    testWidgets('${catalog ? '作品' : '媒体'}入场转场中点击返回只出栈一次', (tester) async {
      final harness = await _mount(
        tester,
        size: const Size(390, 844),
        television: false,
      );
      await _showSection(tester, catalog ? '电影' : '个人视频');
      final card = find
          .byType(catalog ? CatalogCard : MediaCard)
          .hitTestable()
          .first;
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await _back(tester, _Back.button, catalog: catalog);
      expect(_location(harness.router), '/videos');
      expect(find.byType(CatalogPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

ScrollController _scroll(WidgetTester tester, Finder source) => tester
    .widget<CustomScrollView>(
      find
          .descendant(of: source, matching: find.byType(CustomScrollView))
          .first,
    )
    .controller!;

Finder _heading(String title) => find.byWidgetPredicate(
  (widget) => widget is SectionHeader && widget.title == title,
);

Future<void> _showSection(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    _heading(title),
    250,
    scrollable: find
        .descendant(
          of: find.byKey(const PageStorageKey('catalog-overview-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  // 分区标题到达视口后，下一帧才会触发邻近分区资料加载。
  await tester.pumpAndSettle();
}

Future<void> _openAll(WidgetTester tester, String title) async {
  await _showSection(tester, title);
  final button = find.descendant(
    of: _heading(title),
    matching: find.byType(TextButton),
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<FocusNode> _focusCard(WidgetTester tester, Finder card) async {
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  final node = Focus.of(
    tester.element(
      find.descendant(of: card, matching: find.byType(Text)).first,
    ),
  );
  node.requestFocus();
  await tester.pumpAndSettle();
  expect(node.hasPrimaryFocus, isTrue);
  return node;
}

Future<void> _back(
  WidgetTester tester,
  _Back input, {
  required bool catalog,
}) async {
  switch (input) {
    case _Back.button:
      await tester.tap(
        catalog
            ? find.byKey(const ValueKey('catalog-detail-back'))
            : find.byType(BackButton),
      );
    case _Back.system:
      await tester.binding.handlePopRoute();
    case _Back.escape:
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  }
  await tester.pumpAndSettle();
}

Future<({GoRouter router, AppDependencies dependencies})> _mount(
  WidgetTester tester, {
  required Size size,
  required bool television,
  String initialLocation = '/videos',
  _DetailState detailState = _DetailState.ready,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dependencies = AppDependencies(
    mediaRepository: _MediaRepository(detailState),
    catalogRepository: _CatalogRepository(detailState),
    connectionService: MockConnectionService(),
    deviceProfile: television
        ? AppDeviceProfile.television
        : AppDeviceProfile.standard,
  );
  dependencies.session.connect(
    const ServerProfile(
      name: 'detail-back',
      address: 'http://server.local:8080',
      token: 'token',
      hostName: 'server.local',
    ),
  );
  final router = createAppRouter(dependencies)..go(initialLocation);
  addTearDown(router.dispose);
  addTearDown(dependencies.dispose);
  final theme = size.width == 1280 && !television
      ? LumaTheme.light().copyWith(platform: TargetPlatform.windows)
      : LumaTheme.dark();
  await tester.pumpWidget(
    AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(
        theme: television ? applyTvTheme(theme) : theme,
        routerConfig: router,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }
  if (television && initialLocation == '/videos') {
    final navigation = tester
        .widgetList<Focus>(find.byType(Focus))
        .firstWhere((widget) => widget.focusNode?.debugLabel == 'tv-nav-videos')
        .focusNode!;
    navigation.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
  }
  return (router: router, dependencies: dependencies);
}

class _CatalogRepository implements CatalogRepository {
  _CatalogRepository(this.state);
  final _DetailState state;
  final _pending = Completer<CatalogItem>();
  final items = [
    for (final kind in CatalogKind.values)
      for (var index = 0; index < 36; index++)
        CatalogItem(
          id: '${kind.name}-$index',
          sourceId: 'source',
          kind: kind,
          title: '${kind == CatalogKind.movie ? '电影' : '电视剧'} $index',
          year: 2026,
          mediaCount: 1,
          episodeCount: kind == CatalogKind.series ? 1 : 0,
          completedCount: 0,
          playableMediaId: 'personal-0',
          thumbnailUrl: '',
          posterUrl: '',
          durationMs: 2700000,
          resolution: '1080p',
          progressMs: 0,
          completed: false,
          updatedAt: DateTime(2026, 10, 5),
        ),
  ];

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async =>
      items.where((item) => kind == null || item.kind == kind).toList();

  @override
  Future<CatalogItem> detail(String id) async => switch (state) {
    _DetailState.ready => items.firstWhere((item) => item.id == id),
    _DetailState.loading => await _pending.future,
    _DetailState.error => throw StateError('资料暂不可用'),
  };

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async => CatalogFavorite(favorite: favorite, revision: revision + 1);
}

class _MediaRepository extends MockMediaRepository {
  _MediaRepository(this.state);
  final _DetailState state;
  final _pending = Completer<MediaItem>();
  final items = [
    for (var index = 0; index < 36; index++)
      MediaItem(
        id: 'personal-$index',
        title: '个人视频 $index',
        type: MediaType.video,
        duration: const Duration(minutes: 45),
        resolution: '1080p',
        format: 'MP4',
        fileSize: '1 GB',
        directory: '/personal',
        tags: const [],
        addedAt: DateTime(2026, 10, 5),
        artSeed: index,
      ),
  ];

  @override
  Future<List<MediaItem>> loadMedia() async => items;

  @override
  Future<List<MediaItem>> loadContinueWatching() async => [];

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async {
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + (limit ?? items.length)).clamp(0, items.length);
    return MediaListPage(
      items: items.sublist(start, end),
      nextCursor: end == items.length ? null : '$end',
    );
  }

  @override
  Future<MediaItem> loadDetail(String id) async => switch (state) {
    _DetailState.ready => items.firstWhere((item) => item.id == id),
    _DetailState.loading => await _pending.future,
    _DetailState.error => throw StateError('媒体暂不可用'),
  };
}
