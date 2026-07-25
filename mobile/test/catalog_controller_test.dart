import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/api_catalog.dart';
import 'package:luma/data/repositories/catalog_repository.dart';
import 'package:luma/features/catalog/catalog_controller.dart';

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

  @override
  Future<void> ignore(String mediaId) => throw UnimplementedError();

  @override
  Future<List<CatalogIssue>> issues() => throw UnimplementedError();

  @override
  Future<void> updateMatch({
    required String mediaId,
    required CatalogKind kind,
    required String title,
    int? year,
    int? seasonNumber,
    int? episodeNumber,
  }) => throw UnimplementedError();
}
