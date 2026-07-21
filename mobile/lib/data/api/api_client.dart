// Raw HTTP transport. JSON-to-model conversion belongs in data/decoders.
import 'package:dio/dio.dart';

import 'api_exception.dart';

final class ApiClient {
  ApiClient(this._dio, {String apiPrefix = defaultApiPrefix})
    : _apiPrefix = _normalizePrefix(apiPrefix);

  static const defaultApiPrefix = '/api/v1';

  final Dio _dio;
  final String _apiPrefix;

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

  Future<Map<String, dynamic>> getMedia({
    String? query,
    String? type,
    bool? favorite,
    String? tagId,
    String? watchStatus,
    String? sort,
    String? order,
    String? cursor,
    int? limit,
  }) => _json(
    'GET',
    _api('/media'),
    queryParameters: {
      'q': ?query,
      'type': ?type,
      'favorite': ?favorite,
      'tag_id': ?tagId,
      'watch_status': ?watchStatus,
      'sort': ?sort,
      'order': ?order,
      'cursor': ?cursor,
      'limit': ?limit,
    },
  );

  Future<Map<String, dynamic>> getContinueWatching({
    String? cursor,
    int? limit,
  }) => _json(
    'GET',
    _api('/media/continue-watching'),
    queryParameters: {'cursor': ?cursor, 'limit': ?limit},
  );

  Future<Map<String, dynamic>> getMediaDetail(String id) =>
      _json('GET', _api('/media/${_segment(id)}'));

  String thumbnailPath(String id) => _api('/media/${_segment(id)}/thumbnail');

  String streamPath(String id) => _api('/media/${_segment(id)}/stream');

  String originalPath(String id) => _api('/media/${_segment(id)}/original');

  Future<Response<List<int>>> getThumbnail(String id, {String? etag}) =>
      _bytes(thumbnailPath(id), headers: {'If-None-Match': ?etag});

  Future<Response<List<int>>> getStream(
    String id, {
    String? range,
    String? etag,
    String? modifiedSince,
    String? ifRange,
  }) => _bytes(
    streamPath(id),
    headers: {
      'Range': ?range,
      'If-None-Match': ?etag,
      'If-Modified-Since': ?modifiedSince,
      'If-Range': ?ifRange,
    },
  );

  Future<Response<void>> headStream(
    String id, {
    String? etag,
    String? modifiedSince,
  }) => _empty(
    'HEAD',
    streamPath(id),
    headers: {'If-None-Match': ?etag, 'If-Modified-Since': ?modifiedSince},
  );

  Future<Response<List<int>>> getOriginal(
    String id, {
    String? range,
    String? etag,
    String? modifiedSince,
    String? ifRange,
  }) => _bytes(
    originalPath(id),
    headers: {
      'Range': ?range,
      'If-None-Match': ?etag,
      'If-Modified-Since': ?modifiedSince,
      'If-Range': ?ifRange,
    },
  );

  Future<Response<void>> headOriginal(
    String id, {
    String? etag,
    String? modifiedSince,
  }) => _empty(
    'HEAD',
    originalPath(id),
    headers: {'If-None-Match': ?etag, 'If-Modified-Since': ?modifiedSince},
  );

  Future<Map<String, dynamic>> getUserData(String mediaId) =>
      _json('GET', _api('/media/${_segment(mediaId)}/user-data'));

  Future<Map<String, dynamic>> updateUserData(
    String mediaId,
    Map<String, dynamic> changes,
  ) => _json(
    'PATCH',
    _api('/media/${_segment(mediaId)}/user-data'),
    data: changes,
  );

  Future<Map<String, dynamic>> updateProgress({
    required String mediaId,
    required int positionMs,
    required int baseRevision,
  }) => _json(
    'PUT',
    _api('/media/${_segment(mediaId)}/progress'),
    data: {'position_ms': positionMs, 'base_revision': baseRevision},
  );

  Future<Map<String, dynamic>> getTags() => _json('GET', _api('/tags'));

  Future<Map<String, dynamic>> createTag(String name) =>
      _json('POST', _api('/tags'), data: {'name': name});

  Future<Map<String, dynamic>> updateTag({
    required String id,
    required String name,
    required int baseRevision,
  }) => _json(
    'PATCH',
    _api('/tags/${_segment(id)}'),
    data: {'name': name, 'base_revision': baseRevision},
  );

  Future<Response<void>> deleteTag(String id) =>
      _empty('DELETE', _api('/tags/${_segment(id)}'));

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, responseType: ResponseType.json),
      );
      final body = response.data;
      if (body is Map<String, dynamic>) return body;
      if (body is Map) return Map<String, dynamic>.from(body);
      throw const ApiException(message: 'Expected a JSON object response');
    } on DioException catch (error) {
      throw error.error is ApiException
          ? error.error! as ApiException
          : ApiException.fromDio(error);
    }
  }

  Future<Response<List<int>>> _bytes(
    String path, {
    Map<String, dynamic>? headers,
  }) async {
    try {
      return await _dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          validateStatus: _acceptSuccessOrNotModified,
        ),
      );
    } on DioException catch (error) {
      throw error.error is ApiException
          ? error.error! as ApiException
          : ApiException.fromDio(error);
    }
  }

  Future<Response<void>> _empty(
    String method,
    String path, {
    Map<String, dynamic>? headers,
  }) async {
    try {
      return await _dio.request<void>(
        path,
        options: Options(
          method: method,
          headers: headers,
          validateStatus: _acceptSuccessOrNotModified,
        ),
      );
    } on DioException catch (error) {
      throw error.error is ApiException
          ? error.error! as ApiException
          : ApiException.fromDio(error);
    }
  }

  static String _segment(String value) => Uri.encodeComponent(value);

  String _api(String path) => '$_apiPrefix$path';

  static String _normalizePrefix(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '/') return '';
    final withLeadingSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return withLeadingSlash.replaceFirst(RegExp(r'/+$'), '');
  }

  static bool _acceptSuccessOrNotModified(int? status) =>
      status != null && status >= 200 && status < 400;
}
