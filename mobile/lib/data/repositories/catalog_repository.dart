import '../models/api_catalog.dart';

abstract interface class CatalogRepository {
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query});
  Future<CatalogItem> detail(String id);
  Future<List<CatalogIssue>> issues();
  Future<void> updateMatch({
    required String mediaId,
    required CatalogKind kind,
    required String title,
    int? year,
    int? seasonNumber,
    int? episodeNumber,
  });
  Future<void> ignore(String mediaId);
}

final class EmptyCatalogRepository implements CatalogRepository {
  const EmptyCatalogRepository();

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async =>
      [];
  @override
  Future<CatalogItem> detail(String id) =>
      Future.error(StateError('Catalog repository is unavailable'));
  @override
  Future<List<CatalogIssue>> issues() async => [];
  @override
  Future<void> ignore(String mediaId) async {}
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
