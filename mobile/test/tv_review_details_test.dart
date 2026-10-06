// 详情回归覆盖媒体动作、只读资料滚动、作品选集及版本刷新。
// 通过真实页面、主题与焦点组件消费仓储数据；测试各自持有依赖，卸载后释放。
// 延迟仓储只控制刷新时机，断言可见按钮、播放目标和文字几何。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/core/theme/tv_theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_detail_page.dart';
import 'package:luma/features/catalog/widgets/catalog_detail_sections.dart';
import 'package:luma/features/details/media_detail_page.dart';
import 'package:luma/features/details/widgets/tv_scrollable_detail_region.dart';

void main() {
  testWidgets('TV 媒体首屏横幅内左右切换播放与收藏，确认只切换收藏', (tester) async {
    final media = _DetailMediaRepository(_media());
    await _mount(
      tester,
      size: const Size(960, 540),
      media: media,
      page: MediaDetailPage(mediaId: media.item.id, initialItem: media.item),
    );
    final play = find.byType(FilledButton);
    final favorite = find.byKey(const ValueKey('detail-favorite-action'));
    expect(_node(tester, play).hasPrimaryFocus, isTrue);
    final header = find.byKey(const ValueKey('tv-media-viewing-header'));
    expect(header, findsOneWidget);
    expect(find.descendant(of: header, matching: play), findsOneWidget);
    expect(find.descendant(of: header, matching: favorite), findsOneWidget);
    expect(tester.getRect(play).center.dy, tester.getRect(favorite).center.dy);
    _expectVisible(tester, play);
    _expectVisible(tester, favorite);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_node(tester, favorite).hasPrimaryFocus, isTrue);
    _expectVisible(tester, favorite);
    await _press(tester, LogicalKeyboardKey.select);
    expect(media.item.isFavorite, isTrue);
    expect(
      find.descendant(of: favorite, matching: find.text('已收藏')),
      findsOneWidget,
    );
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_node(tester, play).hasPrimaryFocus, isTrue);
    _expectVisible(tester, play);
  });

  for (final unavailable in [false, true]) {
    testWidgets('TV 窄屏竖图首焦点可见：${unavailable ? '收藏回退' : '查看大图'}', (
      tester,
    ) async {
      final media = _DetailMediaRepository(
        _media(image: !unavailable, portrait: true, unavailable: unavailable),
      );
      await _mount(
        tester,
        size: const Size(720, 540),
        media: media,
        page: MediaDetailPage(mediaId: media.item.id, initialItem: media.item),
      );
      final action = unavailable
          ? find.byKey(const ValueKey('detail-favorite-action'))
          : find.byType(FilledButton);
      expect(_node(tester, action).hasPrimaryFocus, isTrue);
      _expectVisible(tester, action);
      if (unavailable) {
        await _press(tester, LogicalKeyboardKey.select);
        expect(media.item.isFavorite, isTrue);
      } else {
        expect(
          find.descendant(of: action, matching: find.text('查看大图')),
          findsOneWidget,
        );
      }
    });
  }

  for (final playable in [true, false]) {
    testWidgets('TV 960×540 作品首焦点可见：${playable ? '播放' : '收藏回退'}', (
      tester,
    ) async {
      final item = _catalog(playable: playable);
      final repository = _DetailCatalogRepository(item);
      final played = <String>[];
      await _mount(
        tester,
        size: const Size(960, 540),
        brightness: playable ? Brightness.light : Brightness.dark,
        page: _catalogPage(item, repository, played),
      );
      final cinematic = find.byKey(
        const ValueKey('tv-catalog-cinematic-header'),
      );
      final identity = find.byKey(const ValueKey('tv-catalog-identity'));
      expect(cinematic, findsOneWidget);
      expect(tester.getSize(cinematic).aspectRatio, greaterThan(1.5));
      expect(
        tester.getRect(identity).top,
        greaterThanOrEqualTo(tester.getRect(cinematic).bottom),
      );
      expect(
        find.descendant(of: cinematic, matching: find.byType(FilledButton)),
        findsOneWidget,
      );
      final theme = Theme.of(
        tester.element(find.byKey(const ValueKey('tv-catalog-play'))),
      );
      expect(theme.brightness, playable ? Brightness.light : Brightness.dark);
      expect(
        theme.colorScheme.surface,
        playable
            ? LumaTheme.light().colorScheme.surface
            : LumaTheme.dark().colorScheme.surface,
      );
      final action = playable
          ? find.byType(FilledButton)
          : find.widgetWithText(OutlinedButton, '加入喜欢');
      expect(_node(tester, action).hasPrimaryFocus, isTrue);
      _expectVisible(tester, action);
      await _press(tester, LogicalKeyboardKey.select);
      if (playable) {
        expect(played, ['primary-media']);
      } else {
        expect(find.widgetWithText(OutlinedButton, '已收藏'), findsOneWidget);
        expect(repository.savedFavorite, isTrue);
      }
    });
  }

  testWidgets('TV 作品首屏播放与收藏同排，遥控下移可进入选集', (tester) async {
    final item = _catalog(episodeCount: 3);
    final repository = _DetailCatalogRepository(item);
    final played = <String>[];
    await _mount(
      tester,
      size: const Size(1280, 720),
      page: _catalogPage(item, repository, played),
    );
    final play = find.byKey(const ValueKey('tv-catalog-play'));
    final favorite = find.widgetWithText(OutlinedButton, '加入喜欢');
    expect(tester.getRect(play).center.dy, tester.getRect(favorite).center.dy);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_node(tester, favorite).hasPrimaryFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(repository.savedFavorite, isTrue);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_node(tester, play).hasPrimaryFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final first = find.byKey(const ValueKey('episode-1'));
    expect(first, findsOneWidget);
    expect(_node(tester, first).hasPrimaryFocus, isTrue);
    _expectVisible(tester, first);
    await _press(tester, LogicalKeyboardKey.select);
    expect(played, ['episode-media-1']);
  });

  testWidgets('TV 长简介只滚动自身范围并向下交接第一集', (tester) async {
    final item = _catalog(
      episodeCount: 100,
      overview: List.filled(15, '这是一段需要遥控器逐屏阅读的作品简介。').join('\n'),
    );
    final played = <String>[];
    await _mount(
      tester,
      size: const Size(960, 540),
      page: _catalogPage(item, _DetailCatalogRepository(item), played),
    );
    final region = find.byType(TvScrollableDetailRegion);
    await tester.scrollUntilVisible(region, 250);
    await tester.pumpAndSettle();
    final regionNode = tester
        .widget<Focus>(
          find.descendant(of: region, matching: find.byType(Focus)).first,
        )
        .focusNode!;
    regionNode.requestFocus();
    await tester.pumpAndSettle();
    expect(regionNode.hasPrimaryFocus, isTrue);
    final scrollable = Scrollable.of(tester.element(region));
    expect(
      tester.getSize(region).height,
      greaterThan(scrollable.position.viewportDimension),
      reason: '简介必须实际超过一屏，才能验证区域内翻页',
    );
    final before = scrollable.position.pixels;
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(scrollable.position.pixels, greaterThan(before));
    // 简介约两屏；集合后续一百集不属于这块文字的滚动范围。
    for (var step = 0; step < 7 && regionNode.hasPrimaryFocus; step++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    final first = find.byKey(const ValueKey('episode-1'));
    expect(first, findsOneWidget);
    expect(_node(tester, first).hasPrimaryFocus, isTrue);
    _expectVisible(tester, first);
    await _press(tester, LogicalKeyboardKey.select);
    expect(played, ['episode-media-1']);
  });

  testWidgets('TV 1.5 倍两行选集无重叠，跨季遥控揭示和播放一致', (tester) async {
    final item = _catalog(episodeCount: 36, longEpisodeTitles: true);
    final played = <String>[];
    await _mount(
      tester,
      size: const Size(960, 540),
      textScale: 1.5,
      page: _catalogPage(item, _DetailCatalogRepository(item), played),
    );
    final first = find.byKey(const ValueKey('episode-1'));
    await tester.scrollUntilVisible(first, 250);
    await tester.pumpAndSettle();
    _node(tester, first).requestFocus();
    await tester.pumpAndSettle();
    for (var number = 1; number <= 19; number++) {
      final tile = find.byKey(ValueKey('episode-$number'));
      expect(tile, findsOneWidget);
      expect(_node(tester, tile).hasPrimaryFocus, isTrue);
      _expectVisible(tester, tile);
      final texts = find.descendant(of: tile, matching: find.byType(Text));
      final title = tester.getRect(texts.at(0));
      final metadata = tester.getRect(texts.at(1));
      final tileRect = tester.getRect(tile);
      expect(title.height, greaterThan(60), reason: '必须实际覆盖两行大字标题');
      expect(metadata.top, greaterThanOrEqualTo(title.bottom));
      expect(metadata.bottom, lessThanOrEqualTo(tileRect.bottom + 0.5));
      expect(tester.takeException(), isNull);
      if (number < 19) await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.select);
    expect(played, ['episode-media-19']);
  });

  for (final refreshCase in [
    'leave-primary',
    'reorder-focused',
    'remove-focused',
  ]) {
    testWidgets('TV 电影版本刷新保留用户焦点：$refreshCase', (tester) async {
      final item = _catalog(
        versions: [_version('a'), _version('b'), _version('c')],
      );
      final repository = _DetailCatalogRepository(item)
        ..pending = Completer<CatalogItem>();
      final played = <String>[];
      await _mount(
        tester,
        size: const Size(1280, 720),
        settle: false,
        page: _catalogPage(item, repository, played),
      );
      final versionB = _versionTile('b');
      await tester.scrollUntilVisible(versionB, 250);
      await _pumpPendingRefresh(tester);
      _node(tester, versionB).requestFocus();
      await _pumpPendingRefresh(tester);
      expect(_node(tester, versionB).hasPrimaryFocus, isTrue);
      final primary = find.byType(FilledButton);
      if (refreshCase == 'leave-primary') {
        await tester.ensureVisible(primary);
        _node(tester, primary).requestFocus();
        await _pumpPendingRefresh(tester);
      }
      repository.pending!.complete(
        _catalog(
          versions: refreshCase == 'reorder-focused'
              ? [_version('c'), _version('a'), _version('b')]
              : [_version('a'), _version('c')],
        ),
      );
      await tester.pumpAndSettle();
      final expected = refreshCase == 'leave-primary'
          ? primary
          : _versionTile(refreshCase == 'reorder-focused' ? 'b' : 'c');
      expect(_node(tester, expected).hasPrimaryFocus, isTrue);
      _expectVisible(tester, expected);
      await _press(tester, LogicalKeyboardKey.select);
      expect(played, [
        refreshCase == 'leave-primary'
            ? 'primary-media'
            : 'version-${refreshCase == 'reorder-focused' ? 'b' : 'c'}',
      ]);
    });
  }

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('普通端 ${size.width.toInt()} 媒体收藏及作品选集点击键盘回归', (tester) async {
      final media = _DetailMediaRepository(_media());
      await _mount(
        tester,
        size: size,
        television: false,
        brightness: size.width < 600 ? Brightness.light : Brightness.dark,
        media: media,
        page: MediaDetailPage(mediaId: media.item.id, initialItem: media.item),
      );
      final favorite = find.byTooltip('收藏');
      await tester.ensureVisible(favorite);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await tester.tap(favorite);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(media.item.isFavorite, isTrue);
      expect(find.byTooltip('取消收藏'), findsOneWidget);
      expect(find.byType(TvScrollableDetailRegion), findsNothing);
      expect(
        find.byKey(const ValueKey('tv-media-viewing-header')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      // 新路由树避免复用上一页已注册的焦点与控制器。
      await tester.pumpWidget(const SizedBox.shrink());
      final item = _catalog(episodeCount: 3);
      final played = <String>[];
      await _mount(
        tester,
        size: size,
        television: false,
        brightness: size.width < 600 ? Brightness.light : Brightness.dark,
        page: _catalogPage(item, _DetailCatalogRepository(item), played),
      );
      final first = find.byKey(const ValueKey('episode-1'));
      await tester.scrollUntilVisible(first, 250);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      await tester.tap(first);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      _node(tester, first).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.enter);
      expect(played, ['episode-media-1', 'episode-media-1']);
      _expectVisible(tester, first);
      expect(find.byType(TvScrollableDetailRegion), findsNothing);
      expect(
        find.byKey(const ValueKey('tv-catalog-cinematic-header')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required Size size,
  required Widget page,
  bool television = true,
  double textScale = 1,
  Brightness brightness = Brightness.dark,
  MockMediaRepository? media,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dependencies = AppDependencies(
    mediaRepository: media ?? MockMediaRepository(),
    connectionService: MockConnectionService(),
    deviceProfile: television
        ? AppDeviceProfile.television
        : AppDeviceProfile.standard,
  );
  addTearDown(dependencies.dispose);
  final base = brightness == Brightness.dark
      ? LumaTheme.dark()
      : LumaTheme.light();
  await tester.pumpWidget(
    AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: television ? applyTvTheme(base) : base,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  } else {
    await _pumpPendingRefresh(tester);
  }
}

Future<void> _pumpPendingRefresh(WidgetTester tester) async {
  // 背景刷新中的进度条持续重绘；逐帧提交焦点与路由，不等待未放行的网络。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

FocusNode _node(WidgetTester tester, Finder control) => Focus.of(
  tester.element(
    find.descendant(of: control, matching: find.byType(Text)).first,
  ),
);

void _expectVisible(WidgetTester tester, Finder control) {
  final rect = tester.getRect(control);
  final viewport = tester.getRect(
    find.ancestor(of: control, matching: find.byType(Scrollable)).first,
  );
  expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.5));
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
  expect(rect.left, greaterThanOrEqualTo(viewport.left - 0.5));
  expect(rect.right, lessThanOrEqualTo(viewport.right + 0.5));
  expect(control.hitTestable(), findsOneWidget);
}

Finder _versionTile(String id) => find.byWidgetPredicate(
  (widget) =>
      widget is CatalogVersionTile && widget.version.mediaId == 'version-$id',
);

Widget _catalogPage(
  CatalogItem item,
  CatalogRepository repository,
  List<String> played,
) => CatalogDetailPage(
  catalogId: item.id,
  initialItem: item,
  repository: repository,
  onOpenMedia: played.add,
  onOpenMediaFromStart: played.add,
  onWarmStream: (_) async {},
);

MediaItem _media({
  bool image = false,
  bool portrait = false,
  bool unavailable = false,
}) => MediaItem(
  id: 'detail-media',
  title: '详情回归媒体',
  type: image ? MediaType.image : MediaType.video,
  duration: const Duration(minutes: 45),
  resolution: '1920×1080',
  format: image ? 'JPEG' : 'MP4',
  fileSize: '1 GB',
  directory: '/library/details',
  tags: const ['资料'],
  addedAt: DateTime(2026, 10, 5),
  artSeed: 1,
  aspectRatio: portrait ? 0.6 : 16 / 9,
  note: List.filled(12, '需要阅读的媒体备注与文件说明。').join('\n'),
  status: unavailable ? 'pending' : 'ready',
);

CatalogItem _catalog({
  bool playable = true,
  int episodeCount = 0,
  bool longEpisodeTitles = false,
  String overview = '',
  List<CatalogVersion> versions = const [],
}) => CatalogItem(
  id: 'detail-catalog',
  sourceId: 'source',
  kind: episodeCount > 0 ? CatalogKind.series : CatalogKind.movie,
  title: '作品详情回归',
  year: 2026,
  mediaCount: episodeCount > 0 ? episodeCount : versions.length,
  episodeCount: episodeCount,
  completedCount: 0,
  playableMediaId: playable ? 'primary-media' : '',
  thumbnailUrl: '',
  posterUrl: '',
  durationMs: 2700000,
  resolution: '1080p',
  progressMs: 0,
  completed: false,
  updatedAt: DateTime(2026, 10, 5),
  overview: overview,
  versions: versions,
  episodes: [
    for (var i = 1; i <= episodeCount; i++)
      CatalogEpisode(
        id: 'episode-$i',
        seasonNumber: (i - 1) ~/ 12 + 1,
        episodeNumber: (i - 1) % 12 + 1,
        title: longEpisodeTitles
            ? '漫长旅程中的重逢与告别，穿越山川寻找那些失落的记忆和未曾说出口的约定'
            : '旅程 $i',
        mediaId: 'episode-media-$i',
        durationMs: 2700000,
        resolution: '1920×1080',
        progressMs: 0,
        completed: false,
        thumbnailUrl: '',
      ),
  ],
);

CatalogVersion _version(String id) => CatalogVersion(
  mediaId: 'version-$id',
  label: '版本 $id',
  fileSize: 0,
  durationMs: 2700000,
  resolution: '1080p',
  videoCodec: 'h264',
  audioCodec: 'aac',
  audioTrackCount: 1,
  progressMs: 0,
  completed: false,
  selected: id == 'a',
);

class _DetailMediaRepository extends MockMediaRepository {
  _DetailMediaRepository(this.item);
  MediaItem item;

  @override
  Future<MediaItem> loadDetail(String id) async => item;

  @override
  Future<MediaItem> setFavorite(String id, bool value) async {
    item = item.copyWith(isFavorite: value);
    return item;
  }
}

class _DetailCatalogRepository implements CatalogRepository {
  _DetailCatalogRepository(this.item);
  final CatalogItem item;
  Completer<CatalogItem>? pending;
  bool? savedFavorite;

  @override
  Future<CatalogItem> detail(String id) async =>
      pending == null ? item : await pending!.future;

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async {
    savedFavorite = favorite;
    return CatalogFavorite(favorite: favorite, revision: revision + 1);
  }

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async => [
    item,
  ];
}
