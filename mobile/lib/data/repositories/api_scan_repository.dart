// Adapts source and scan-job endpoints for the aggregate scan UI.
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../decoders/scan_job_decoder.dart';
import '../models/api_scan.dart';
import 'source_repository.dart';
import 'scan_repository.dart';

final class ApiScanRepository implements ScanRepository {
  ApiScanRepository(this._client, this._sources);

  final ApiClient _client;
  final SourceRepository _sources;
  final ScanJobDecoder _scanDecoder = const ScanJobDecoder();

  @override
  /// Starts one backend scan job for every enabled source.
  /// Partial failures (e.g. SCAN_ALREADY_RUNNING) do not abort other sources.
  Future<List<ScanJob>> startAll() async {
    final sources = (await _sources.list(
      refresh: true,
    )).where((source) => source.enabled).toList(growable: false);
    final jobs = <ScanJob>[];
    final errors = <String>[];
    for (final source in sources) {
      try {
        jobs.add(_scanDecoder.decode(await _client.startScan(source.id)));
      } on ApiException catch (error) {
        errors.add('${source.name}: ${error.message}');
      } on Object catch (error) {
        errors.add('${source.name}: $error');
      }
    }
    if (jobs.isEmpty) {
      throw StateError(errors.isEmpty ? '没有可扫描的媒体源' : errors.join('；'));
    }
    return jobs;
  }

  @override
  Future<ScanJob?> latest() async {
    try {
      return _scanDecoder.decode(await _client.getLatestScan());
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<ScanJob>> latestAll() async {
    final sources = (await _sources.list(
      refresh: true,
    )).where((source) => source.enabled).toList(growable: false);
    final jobs = <ScanJob>[];
    for (final source in sources) {
      try {
        jobs.add(
          _scanDecoder.decode(await _client.getLatestScan(sourceId: source.id)),
        );
      } on ApiException catch (error) {
        if (error.statusCode != 404) rethrow;
      }
    }
    return jobs;
  }

  @override
  Future<ScanJob> get(String id) async =>
      _scanDecoder.decode(await _client.getScanJob(id));
}
