import '../api/api_client.dart';
import '../decoders/catalog_decoder.dart';
import '../models/api_catalog.dart';
import 'catalog_repository.dart';

final class ApiCatalogRepository implements CatalogRepository {
  ApiCatalogRepository(this._client);

  final ApiClient _client;
  final CatalogDecoder _decoder = const CatalogDecoder();

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async =>
      _decoder.decodeList(
        await _client.getCatalog(kind: kind?.name, query: query),
      );

  @override
  Future<CatalogItem> detail(String id) async =>
      _decoder.decode(await _client.getCatalogDetail(id));

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async {
    final data = await _client.updateCatalogUserData(catalogId, {
      'favorite': favorite,
      'base_revision': revision,
    });
    return CatalogFavorite(
      favorite: data['favorite'] as bool? ?? favorite,
      revision: data['revision'] as int? ?? revision + 1,
    );
  }

}
