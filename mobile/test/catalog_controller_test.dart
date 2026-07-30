import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_controller.dart';
import 'package:luma/features/catalog/catalog_store.dart';

void main() {
  test(
    'catalog controller defers its first request until explicitly loaded',
    () async {
      final repository = _BlockingCatalogRepository();
      final controller = CatalogController(repository, kind: CatalogKind.movie);
      addTearDown(controller.dispose);

      expect(controller.state, CatalogLoadState.idle);
      expect(repository.calls, 0);

      final first = controller.ensureLoaded();
      final duplicate = controller.ensureLoaded();
      expect(repository.calls, 1);

      repository.complete();
      await Future.wait([first, duplicate]);
      expect(controller.state, CatalogLoadState.ready);
      expect(controller.hasStarted, isTrue);
    },
  );

  test('a disposed catalog controller ignores a late response', () async {
    final repository = _BlockingCatalogRepository();
    final controller = CatalogController(repository, kind: CatalogKind.series);
    final request = controller.ensureLoaded();
    controller.dispose();

    repository.complete();
    await request;
    expect(controller.items, isEmpty);
  });

  test(
    'catalog invalidation refreshes a started list and shares detail data',
    () async {
      final repository = _RefreshingCatalogRepository();
      final store = CatalogStore(repository);
      final controller = CatalogController(store, kind: CatalogKind.movie);
      addTearDown(() {
        controller.dispose();
        store.dispose();
      });

      await controller.ensureLoaded();
      expect(controller.items.single.progressMs, 0);

      await store.detail('catalog-1');
      expect(controller.items.single.progressMs, 500);

      store.invalidate('catalog-1');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(repository.listCalls, 2);
      expect(controller.items.single.progressMs, 1000);
      expect(store.isKindInvalidated(CatalogKind.movie), isFalse);
    },
  );

  test(
    'catalog store keeps the newest favorite revision for stale route data',
    () async {
      final repository = _RefreshingCatalogRepository();
      final store = CatalogStore(repository);
      addTearDown(store.dispose);
      final stale = _catalogItem(progressMs: 0);
      store.rememberAll([stale]);

      await store.setFavorite(
        catalogId: stale.id,
        favorite: true,
        revision: stale.favoriteRevision,
      );

      final favorite = store.favoriteFor(stale);
      expect(favorite.favorite, isTrue);
      expect(favorite.revision, 1);
    },
  );
}

CatalogItem _catalogItem({required int progressMs}) => CatalogItem(
  id: 'catalog-1',
  sourceId: 'source-1',
  kind: CatalogKind.movie,
  title: '作品',
  year: 2026,
  mediaCount: 1,
  episodeCount: 0,
  completedCount: 0,
  playableMediaId: 'media-1',
  thumbnailUrl: '',
  posterUrl: '',
  durationMs: 2000,
  resolution: '1080p',
  progressMs: progressMs,
  completed: false,
  updatedAt: DateTime(2026, 7, 26),
);

class _RefreshingCatalogRepository implements CatalogRepository {
  var listCalls = 0;

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async {
    listCalls++;
    return [_catalogItem(progressMs: listCalls == 1 ? 0 : 1000)];
  }

  @override
  Future<CatalogItem> detail(String id) async => _catalogItem(progressMs: 500);

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async => CatalogFavorite(favorite: favorite, revision: revision + 1);
}

class _BlockingCatalogRepository implements CatalogRepository {
  final _response = Completer<List<CatalogItem>>();
  var calls = 0;

  void complete() => _response.complete(const []);

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) {
    calls++;
    return _response.future;
  }

  @override
  Future<CatalogItem> detail(String id) => throw UnimplementedError();

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) => throw UnimplementedError();
}
