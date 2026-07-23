// Typed representations of administrator access-control resources.
final class AccessUser {
  const AccessUser({
    required this.id,
    required this.name,
    required this.role,
    required this.enabled,
    this.online = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String role;
  final bool enabled;
  final bool online;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isAdmin => role == 'admin';
}

final class AccessToken {
  const AccessToken({
    required this.id,
    required this.userId,
    required this.name,
    required this.tokenPrefix,
    required this.expiresAt,
    required this.revokedAt,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String name;
  final String tokenPrefix;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final DateTime createdAt;

  bool get isRevoked => revokedAt != null;

  bool get isExpired {
    final expiration = expiresAt;
    return expiration != null && !expiration.isAfter(DateTime.now());
  }
}

final class IssuedAccessToken {
  const IssuedAccessToken({
    required this.id,
    required this.userId,
    required this.name,
    required this.tokenPrefix,
    required this.expiresAt,
    required this.revokedAt,
    required this.createdAt,
    required this.token,
  });

  final String id;
  final String userId;
  final String name;
  final String tokenPrefix;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final DateTime createdAt;

  // The server returns this plaintext value exactly once. Do not persist or log it.
  final String token;
}
