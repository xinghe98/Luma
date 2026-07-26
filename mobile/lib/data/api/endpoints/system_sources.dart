part of '../api_client.dart';

mixin _SystemSourceEndpoints on _ApiTransport {
  Future<Map<String, dynamic>> getHealth() => _json('GET', '/health');

  Future<Map<String, dynamic>> getSystemInfo() =>
      _json('GET', _api('/system/info'));

  Future<Map<String, dynamic>> getSources() => _json('GET', _api('/sources'));

  Future<Map<String, dynamic>> createSource({
    required String name,
    required String rootPath,
  }) => _json(
    'POST',
    _api('/sources'),
    data: {'name': name, 'root_path': rootPath},
  );

  Future<Map<String, dynamic>> createManagedSource({
    required String name,
    required String rootPath,
    required String libraryKind,
    required List<String> userIds,
  }) => _json(
    'POST',
    _api('/admin/media-sources'),
    data: {
      'name': name,
      'root_path': rootPath,
      'library_kind': libraryKind,
      'user_ids': userIds,
    },
  );

  Future<Map<String, dynamic>> getAvailableMediaRoots() =>
      _json('GET', _api('/admin/media-roots'));

  Future<Map<String, dynamic>> updateSource(
    String id,
    Map<String, dynamic> changes,
  ) => _json('PATCH', _api('/sources/${_segment(id)}'), data: changes);

  Future<Response<void>> deleteSource(String id) =>
      _empty('DELETE', _api('/sources/${_segment(id)}'));

  Future<Map<String, dynamic>> startScan(String sourceId) =>
      _json('POST', _api('/sources/${_segment(sourceId)}/scan'));

  Future<Map<String, dynamic>> getLatestScan({String? sourceId}) => _json(
    'GET',
    _api('/scan-jobs/latest'),
    queryParameters: {'source_id': ?sourceId},
  );

  Future<Map<String, dynamic>> getScanJob(String id) =>
      _json('GET', _api('/scan-jobs/${_segment(id)}'));
}
