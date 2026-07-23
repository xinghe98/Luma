// Caches the authenticated source list for the active server session.
import '../api/api_client.dart';
import '../decoders/source_decoder.dart';
import '../decoders/scan_job_decoder.dart';
import '../decoders/decoder_utils.dart';
import '../models/api_managed_source.dart';
import '../models/api_source.dart';
import 'source_repository.dart';

final class ApiSourceRepository
    implements
        MutableSourceRepository,
        SessionSeedableSourceRepository,
        SessionResettableSourceRepository {
  ApiSourceRepository(this._client);

  final ApiClient _client;
  final SourceDecoder _decoder = const SourceDecoder();
  final ScanJobDecoder _scanDecoder = const ScanJobDecoder();
  List<Source>? _cache;

  @override
  void seedSessionCache(List<Source> sources) {
    _cache = List.unmodifiable(sources);
  }

  @override
  void clearSessionCache() => _cache = null;

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

  @override
  Future<Source> updateLibraryKind(String id, String libraryKind) async {
    final source = _decoder.decode(
      await _client.updateSource(id, {'library_kind': libraryKind}),
    );
    _cache = [
      for (final item in _cache ?? await list()) item.id == id ? source : item,
    ];
    return source;
  }

  @override
  Future<ManagedSourceCreation> createManagedSource({
    required String name,
    required String rootPath,
    required String libraryKind,
    required List<String> userIds,
  }) async {
    final response = await _client.createManagedSource(
      name: name,
      rootPath: rootPath,
      libraryKind: libraryKind,
      userIds: userIds,
    );
    final source = _decoder.decode(objectValue(response['source'], 'source'));
    final scanJob = _scanDecoder.decode(
      objectValue(response['scan_job'], 'scan_job'),
    );
    _cache = [...?_cache, source];
    return ManagedSourceCreation(source: source, scanJob: scanJob);
  }
}
