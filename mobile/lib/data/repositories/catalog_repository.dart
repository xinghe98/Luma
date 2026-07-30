import '../models/api_catalog.dart';

abstract interface class CatalogRepository {
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query});
  Future<CatalogItem> detail(String id);

  /// 保存作品级收藏，revision 不一致时由实现抛出接口错误。
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  });
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
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) => Future.error(StateError('Catalog repository is unavailable'));
}
