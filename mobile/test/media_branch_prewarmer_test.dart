// 媒体分支预热专项测试覆盖有界请求、缩略图数量和会话切换隔离。
// 测试使用真实控制器与共享 CatalogStore，但以无网络图片缓存回调替代解码。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_store.dart';
import 'package:luma/features/shell/media_branch_prewarmer.dart';

void main() {
  testWidgets('prewarmer prepares bounded snapshots once per session', (
    tester,
  ) async {
    final media = MediaController(MockMediaRepository());
    final repository = _WarmupCatalogRepository();
    final catalog = CatalogStore(repository);
    final session = ApiSession(
      origin: 'https://luma.test',
      token: 'session-token',
    );
    var precachedImages = 0;
    final prewarmer = MediaBranchPrewarmer(
      media: media,
      catalog: catalog,
      session: session,
      precacheImage: (_, _) async => precachedImages++,
    );
    addTearDown(() {
      prewarmer.dispose();
      catalog.dispose();
      media.dispose();
    });

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    await tester.runAsync(() => prewarmer.warm(context));

    expect(prewarmer.photos.length, lessThanOrEqualTo(12));
    expect(
      prewarmer.catalogItems(CatalogKind.movie),
      hasLength(1),
    );
    expect(
      prewarmer.catalogItems(CatalogKind.series),
      hasLength(1),
    );
    expect(repository.calls, {
      CatalogKind.movie: 1,
      CatalogKind.series: 1,
    });
    expect(precachedImages, lessThanOrEqualTo(6));

    await tester.runAsync(() => prewarmer.warm(context));
    expect(repository.calls, {
      CatalogKind.movie: 1,
      CatalogKind.series: 1,
    });

    session.update(origin: 'https://second.test', token: 'next-token');
    expect(prewarmer.photos, isEmpty);
    expect(prewarmer.catalogItems(CatalogKind.movie), isEmpty);
  });
}

class _WarmupCatalogRepository implements CatalogRepository {
  final Map<CatalogKind, int> calls = {};

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async {
    final resolvedKind = kind ?? CatalogKind.movie;
    calls.update(resolvedKind, (value) => value + 1, ifAbsent: () => 1);
    return [_item(resolvedKind)];
  }

  @override
  Future<CatalogItem> detail(String id) async => _item(CatalogKind.movie);

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async => CatalogFavorite(favorite: favorite, revision: revision);

  CatalogItem _item(CatalogKind kind) => CatalogItem(
    id: 'catalog-${kind.name}',
    sourceId: 'source-1',
    kind: kind,
    title: kind == CatalogKind.movie ? '电影' : '电视剧',
    year: null,
    mediaCount: 1,
    episodeCount: kind == CatalogKind.series ? 1 : 0,
    completedCount: 0,
    playableMediaId: 'media-${kind.name}',
    thumbnailUrl: '/thumbnail-${kind.name}',
    posterUrl: '/poster-${kind.name}',
    durationMs: null,
    resolution: '',
    progressMs: 0,
    completed: false,
    updatedAt: DateTime(2026, 7, 30),
  );
}
