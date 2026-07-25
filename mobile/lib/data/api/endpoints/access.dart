part of '../api_client.dart';

mixin _AccessEndpoints on _ApiTransport {
  Future<Map<String, dynamic>> getAccessUsers() =>
      _json('GET', _api('/admin/users'));

  Future<Map<String, dynamic>> createAccessUser(
    String name, {
    required String username,
    required String password,
    String? requestId,
  }) => _json(
    'POST',
    _api('/admin/users'),
    data: {
      'name': name,
      'username': username,
      'password': password,
      'request_id': ?requestId,
    },
  );

  Future<Map<String, dynamic>> updateAccessUser(
    String id,
    Map<String, dynamic> changes,
  ) => _json('PATCH', _api('/admin/users/${_segment(id)}'), data: changes);

  Future<void> resetAccessPassword(String userId, String password) => _empty(
    'PUT',
    _api('/admin/users/${_segment(userId)}/password'),
    data: {'password': password},
  );

  Future<Map<String, dynamic>> getAccessSessions(String userId) =>
      _json('GET', _api('/admin/users/${_segment(userId)}/sessions'));

  Future<void> revokeAccessSession(String id) =>
      _empty('DELETE', _api('/admin/sessions/${_segment(id)}'));

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
