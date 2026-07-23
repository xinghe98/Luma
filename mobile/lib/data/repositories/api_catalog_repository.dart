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
  Future<List<CatalogIssue>> issues() async =>
      _decoder.decodeIssues(await _client.getCatalogIssues());

  @override
  Future<void> updateMatch({
    required String mediaId,
    required CatalogKind kind,
    required String title,
    int? year,
    int? seasonNumber,
    int? episodeNumber,
  }) => _client.updateCatalogMatch(mediaId, {
    'kind': kind.name,
    'title': title,
    'year': ?year,
    'season_number': ?seasonNumber,
    'episode_number': ?episodeNumber,
  });

  @override
  Future<void> ignore(String mediaId) =>
      _client.updateCatalogMatch(mediaId, {'ignored': true});
}
