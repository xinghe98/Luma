import '../models/api_access.dart';

abstract interface class AccessRepository {
  Future<List<AccessUser>> listUsers();

  Future<AccessUser> createUser(
    String name, {
    required String username,
    required String password,
    String? requestId,
  });

  Future<AccessUser> updateUser(String id, {String? name, bool? enabled});

  Future<void> resetPassword(String userId, String password);

  Future<List<LoginSession>> listSessions(String userId);

  Future<void> revokeSession(String sessionId);

  Future<List<String>> listGrants(String userId);

  Future<void> grantSource(String userId, String sourceId);

  Future<void> revokeSource(String userId, String sourceId);
}

final class UnavailableAccessRepository implements AccessRepository {
  const UnavailableAccessRepository();

  @override
  Future<List<AccessUser>> listUsers() => _unavailable();

  @override
  Future<AccessUser> createUser(
    String name, {
    required String username,
    required String password,
    String? requestId,
  }) => _unavailable();

  @override
  Future<AccessUser> updateUser(String id, {String? name, bool? enabled}) =>
      _unavailable();

  @override
  Future<void> resetPassword(String userId, String password) => _unavailable();

  @override
  Future<List<LoginSession>> listSessions(String userId) => _unavailable();

  @override
  Future<void> revokeSession(String sessionId) => _unavailable();

  @override
  Future<List<String>> listGrants(String userId) => _unavailable();

  @override
  Future<void> grantSource(String userId, String sourceId) => _unavailable();

  @override
  Future<void> revokeSource(String userId, String sourceId) => _unavailable();

  Future<T> _unavailable<T>() =>
      Future<T>.error(StateError('Access repository is unavailable'));
}
