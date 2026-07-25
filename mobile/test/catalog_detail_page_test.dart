// 作品详情页测试覆盖刮削资料的渐进展示，确保刷新时保留已有内容。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_detail_page.dart';

void main() {
  testWidgets('catalog detail keeps scraped content visible while refreshing', (
    tester,
  ) async {
    final item = CatalogItem(
      id: 'catalog-1',
      sourceId: 'source-1',
      kind: CatalogKind.movie,
      title: '三体',
      year: 2023,
      mediaCount: 1,
      episodeCount: 0,
      completedCount: 0,
      playableMediaId: 'media-1',
      thumbnailUrl: '',
      posterUrl: '',
      durationMs: 3600000,
      resolution: '1920×1080',
      progressMs: 0,
      completed: false,
      updatedAt: DateTime(2026, 7, 25),
      overview: '一段跨越时空的故事。',
      certification: 'PG-13',
      communityRating: 8.4,
      genres: [CatalogNamedValue(id: '18', name: '剧情')],
      credits: [
        CatalogCredit(
          personId: 'person-1',
          name: '演员',
          role: 'actor',
          character: '角色',
          order: 0,
        ),
      ],
      metadataStatus: 'refreshing',
      versions: const [
        CatalogVersion(
          mediaId: 'movie-4k',
          label: '4K HEVC',
          fileSize: 2147483648,
          durationMs: 3600000,
          resolution: '3840×2160',
          videoCodec: 'hevc',
          audioCodec: 'aac',
          audioTrackCount: 2,
          progressMs: 0,
          completed: false,
          selected: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CatalogDetailPage(
          catalogId: item.id,
          initialItem: item,
          repository: _CatalogDetailRepository(item),
          onOpenMedia: (_) {},
          onOpenMediaFromStart: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('一段跨越时空的故事。'), findsOneWidget);
    expect(find.text('剧情'), findsOneWidget);
    expect(find.text('★ 8.4'), findsOneWidget);
    expect(find.text('PG-13'), findsOneWidget);
    expect(find.text('演员'), findsOneWidget);
    expect(find.text('角色'), findsOneWidget);
    final avatarSize = tester.getSize(find.byType(ClipOval));
    expect(avatarSize.width, avatarSize.height);
    expect(avatarSize.width, 56);
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('继续观看'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(OutlinedButton),
        matching: find.text('从头播放'),
      ),
      findsOneWidget,
    );
    expect(find.text('本库其他版本'), findsOneWidget);
    expect(find.text('4K HEVC'), findsOneWidget);
    expect(find.text('资料正在更新'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('catalog detail saves a work favorite optimistically', (
    tester,
  ) async {
    final item = CatalogItem(
      id: 'catalog-favorite',
      sourceId: 'source-1',
      kind: CatalogKind.movie,
      title: '电影',
      year: null,
      mediaCount: 1,
      episodeCount: 0,
      completedCount: 0,
      playableMediaId: 'media-1',
      thumbnailUrl: '',
      posterUrl: '',
      durationMs: null,
      resolution: '',
      progressMs: 0,
      completed: false,
      updatedAt: DateTime(2026, 7, 25),
    );
    final repository = _CatalogDetailRepository(item);

    await tester.pumpWidget(
      MaterialApp(
        home: CatalogDetailPage(
          catalogId: item.id,
          initialItem: item,
          repository: repository,
          onOpenMedia: (_) {},
          onOpenMediaFromStart: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('收藏'));
    await tester.pump();

    expect(repository.favoriteCalls, 1);
    expect(find.text('已收藏'), findsOneWidget);
  });
}

class _CatalogDetailRepository implements CatalogRepository {
  _CatalogDetailRepository(this.item);

  final CatalogItem item;
  var favoriteCalls = 0;

  @override
  Future<CatalogItem> detail(String id) async => item;

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async {
    favoriteCalls++;
    return CatalogFavorite(favorite: favorite, revision: revision + 1);
  }

  @override
  Future<void> ignore(String mediaId) async {}

  @override
  Future<List<CatalogIssue>> issues() async => [];

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async =>
      [];

  @override
  Future<void> updateMatch({
    required String mediaId,
    required CatalogKind kind,
    required String title,
    int? year,
    int? seasonNumber,
    int? episodeNumber,
  }) async {}
}
