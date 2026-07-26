part of '../api_client.dart';

mixin _MediaEndpoints on _ApiTransport {
  Future<Map<String, dynamic>> getMedia({
    String? query,
    String? type,
    String? libraryKind,
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
      'library_kind': ?libraryKind,
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

  Future<Map<String, dynamic>> getMediaCount({
    String? query,
    String? type,
    String? libraryKind,
    bool? favorite,
    String? tagId,
    String? watchStatus,
  }) => _json(
    'GET',
    _api('/media/count'),
    queryParameters: {
      'q': ?query,
      'type': ?type,
      'library_kind': ?libraryKind,
      'favorite': ?favorite,
      'tag_id': ?tagId,
      'watch_status': ?watchStatus,
    },
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
}
