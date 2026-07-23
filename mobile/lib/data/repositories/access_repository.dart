import '../models/api_access.dart';

abstract interface class AccessRepository {
  Future<List<AccessUser>> listUsers();

  Future<AccessUser> createUser(String name, {String? requestId});

  Future<AccessUser> updateUser(String id, {String? name, bool? enabled});

  Future<List<AccessToken>> listTokens(String userId);

  Future<IssuedAccessToken> issueToken(
    String userId, {
    required String name,
    DateTime? expiresAt,
    String? requestId,
  });

  Future<void> revokeToken(String tokenId);

  Future<List<String>> listGrants(String userId);

  Future<void> grantSource(String userId, String sourceId);

  Future<void> revokeSource(String userId, String sourceId);
}

/// Used only where application dependencies are constructed without an API client.
final class UnavailableAccessRepository implements AccessRepository {
  const UnavailableAccessRepository();

  @override
  Future<List<AccessUser>> listUsers() => _unavailable();

  @override
  Future<AccessUser> createUser(String name, {String? requestId}) =>
      _unavailable();

  @override
  Future<AccessUser> updateUser(String id, {String? name, bool? enabled}) =>
      _unavailable();

  @override
  Future<List<AccessToken>> listTokens(String userId) => _unavailable();

  @override
  Future<IssuedAccessToken> issueToken(
    String userId, {
    required String name,
    DateTime? expiresAt,
    String? requestId,
  }) => _unavailable();

  @override
  Future<void> revokeToken(String tokenId) => _unavailable();

  @override
  Future<List<String>> listGrants(String userId) => _unavailable();

  @override
  Future<void> grantSource(String userId, String sourceId) => _unavailable();

  @override
  Future<void> revokeSource(String userId, String sourceId) => _unavailable();

  Future<T> _unavailable<T>() =>
      Future<T>.error(StateError('Access repository is unavailable'));
}
