import '../api/api_client.dart';
import '../decoders/decoder_utils.dart';
import '../decoders/media_root_decoder.dart';
import '../decoders/scan_job_decoder.dart';
import '../decoders/source_decoder.dart';
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
  final MediaRootDecoder _rootDecoder = const MediaRootDecoder();
  List<Source>? _cache;
  int? _cacheEpoch;

  /// 用已完成候选探测的来源列表初始化当前会话缓存。
  @override
  void seedSessionCache(List<Source> sources) {
    _cache = List.unmodifiable(sources);
    _cacheEpoch = _client.captureSessionEpoch();
  }

  /// 清除来源缓存及其所属 epoch。
  @override
  void clearSessionCache() {
    _cache = null;
    _cacheEpoch = null;
  }

  /// 返回当前会话的来源列表；刷新结果只会写入同一 epoch 的缓存。
  @override
  Future<List<Source>> list({bool refresh = false}) async {
    final epoch = _client.captureSessionEpoch();
    _discardPreviousSessionCache(epoch);
    if (!refresh && _cache != null) return _cache!;
    final sources = _decoder.decodeList(await _client.getSources());
    _client.ensureSessionEpoch(epoch);
    _cache = sources;
    _cacheEpoch = epoch;
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

  /// 更新库类型并同步当前 epoch 的来源缓存；会话切换时拒绝旧结果。
  @override
  Future<Source> updateLibraryKind(String id, String libraryKind) async {
    final epoch = _client.captureSessionEpoch();
    _discardPreviousSessionCache(epoch);
    final source = _decoder.decode(
      await _client.updateSource(id, {'library_kind': libraryKind}),
    );
    _client.ensureSessionEpoch(epoch);
    final current = _cache ?? await list();
    _client.ensureSessionEpoch(epoch);
    _cache = [for (final item in current) item.id == id ? source : item];
    _cacheEpoch = epoch;
    return source;
  }

  @override
  Future<List<String>> listAvailableRoots() async {
    return _rootDecoder.decodeList(await _client.getAvailableMediaRoots());
  }

  /// 创建托管来源并缓存结果；服务端错误或会话切换时不修改缓存。
  @override
  Future<ManagedSourceCreation> createManagedSource({
    required String name,
    required String rootPath,
    required String libraryKind,
    required List<String> userIds,
  }) async {
    final epoch = _client.captureSessionEpoch();
    _discardPreviousSessionCache(epoch);
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
    _client.ensureSessionEpoch(epoch);
    _cache = [...?_cache, source];
    _cacheEpoch = epoch;
    return ManagedSourceCreation(source: source, scanJob: scanJob);
  }

  void _discardPreviousSessionCache(int epoch) {
    if (_cacheEpoch == null || _cacheEpoch == epoch) return;
    _cache = null;
    _cacheEpoch = null;
  }
}
