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
  Future<AccessUser> createUser(String name, {String? requestId}) async =>
      _decoder.decodeUser(
        await _client.createAccessUser(name, requestId: requestId),
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
  Future<List<AccessToken>> listTokens(String userId) async =>
      _decoder.decodeTokenList(await _client.getAccessTokens(userId));

  @override
  Future<IssuedAccessToken> issueToken(
    String userId, {
    required String name,
    DateTime? expiresAt,
    String? requestId,
  }) async => _decoder.decodeIssuedToken(
    await _client.issueAccessToken(userId, {
      'name': name,
      if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
    }, requestId: requestId),
  );

  @override
  Future<void> revokeToken(String tokenId) =>
      _client.revokeAccessToken(tokenId);

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
