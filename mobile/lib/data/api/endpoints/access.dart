part of '../api_client.dart';

mixin _AccessEndpoints on _ApiTransport {
  Future<Map<String, dynamic>> getAccessUsers() =>
      _json('GET', _api('/admin/users'));

  Future<Map<String, dynamic>> createAccessUser(
    String name, {
    String? requestId,
  }) => _json(
    'POST',
    _api('/admin/users'),
    data: {'name': name, 'request_id': ?requestId},
  );

  Future<Map<String, dynamic>> updateAccessUser(
    String id,
    Map<String, dynamic> changes,
  ) => _json('PATCH', _api('/admin/users/${_segment(id)}'), data: changes);

  Future<Map<String, dynamic>> getAccessTokens(String userId) =>
      _json('GET', _api('/admin/users/${_segment(userId)}/tokens'));

  Future<Map<String, dynamic>> issueAccessToken(
    String userId,
    Map<String, dynamic> data, {
    String? requestId,
  }) => _json(
    'POST',
    _api('/admin/users/${_segment(userId)}/tokens'),
    data: {...data, 'request_id': ?requestId},
  );

  Future<void> revokeAccessToken(String id) async {
    await _empty('DELETE', _api('/admin/tokens/${_segment(id)}'));
  }

  Future<Map<String, dynamic>> getAccessGrants(String userId) =>
      _json('GET', _api('/admin/users/${_segment(userId)}/sources'));

  Future<void> grantAccessSource(String userId, String sourceId) async {
    await _empty(
      'PUT',
      _api('/admin/users/${_segment(userId)}/sources/${_segment(sourceId)}'),
    );
  }

  Future<void> revokeAccessSource(String userId, String sourceId) async {
    await _empty(
      'DELETE',
      _api('/admin/users/${_segment(userId)}/sources/${_segment(sourceId)}'),
    );
  }

}
