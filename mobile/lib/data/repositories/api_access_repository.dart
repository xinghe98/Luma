import '../api/api_client.dart';
import '../decoders/access_decoder.dart';
import '../models/api_access.dart';
import 'access_repository.dart';

final class ApiAccessRepository implements AccessRepository {
  ApiAccessRepository(this._client);

  final ApiClient _client;
  final AccessDecoder _decoder = const AccessDecoder();

  @override
  Future<List<AccessUser>> listUsers() async =>
      _decoder.decodeUserList(await _client.getAccessUsers());

  @override
  Future<AccessUser> createUser(
    String name, {
    required String username,
    required String password,
    String? requestId,
  }) async => _decoder.decodeUser(
    await _client.createAccessUser(
      name,
      username: username,
      password: password,
      requestId: requestId,
    ),
  );

  @override
  Future<AccessUser> updateUser(
    String id, {
    String? name,
    bool? enabled,
  }) async => _decoder.decodeUser(
    await _client.updateAccessUser(id, {'name': ?name, 'enabled': ?enabled}),
  );

  @override
  Future<void> resetPassword(String userId, String password) =>
      _client.resetAccessPassword(userId, password);

  @override
  Future<List<LoginSession>> listSessions(String userId) async =>
      _decoder.decodeSessionList(await _client.getAccessSessions(userId));

  @override
  Future<void> revokeSession(String sessionId) =>
      _client.revokeAccessSession(sessionId);

  @override
  Future<List<String>> listGrants(String userId) async =>
      _decoder.decodeGrantIds(await _client.getAccessGrants(userId));

  @override
  Future<void> grantSource(String userId, String sourceId) =>
      _client.grantAccessSource(userId, sourceId);

  @override
  Future<void> revokeSource(String userId, String sourceId) =>
      _client.revokeAccessSource(userId, sourceId);
}
