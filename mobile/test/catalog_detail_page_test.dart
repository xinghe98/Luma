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
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CatalogDetailPage(
          catalogId: item.id,
          initialItem: item,
          repository: _CatalogDetailRepository(item),
          onOpenMedia: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('一段跨越时空的故事。'), findsOneWidget);
    expect(find.text('剧情 · 评分 8.4 · PG-13'), findsOneWidget);
    expect(find.text('演员 · 角色'), findsOneWidget);
    expect(find.text('资料正在更新'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _CatalogDetailRepository implements CatalogRepository {
  const _CatalogDetailRepository(this.item);

  final CatalogItem item;

  @override
  Future<CatalogItem> detail(String id) async => item;

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
