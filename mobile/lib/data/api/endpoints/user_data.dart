part of '../api_client.dart';

mixin _UserDataEndpoints on _ApiTransport {
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

}
