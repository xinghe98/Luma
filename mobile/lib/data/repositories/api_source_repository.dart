// Caches the authenticated source list for the active server session.
import '../api/api_client.dart';
import '../decoders/source_decoder.dart';
import '../models/api_source.dart';
import 'source_repository.dart';

final class ApiSourceRepository implements SourceRepository {
  ApiSourceRepository(this._client);

  final ApiClient _client;
  final SourceDecoder _decoder = const SourceDecoder();
  List<Source>? _cache;

  @override
  Future<List<Source>> list({bool refresh = false}) async {
    if (!refresh && _cache != null) return _cache!;
    final sources = _decoder.decodeList(await _client.getSources());
    _cache = sources;
    return sources;
  }

  @override
  Future<Source?> find(String id) async {
    final sources = await list();
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }
}
