final class AccessUser {
  const AccessUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    required this.enabled,
    this.online = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String username;
  final String role;
  final bool enabled;
  final bool online;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isAdmin => role == 'admin';
}

/// LoginSession 表示管理员可撤销的一台已登录设备。
final class LoginSession {
  const LoginSession({
    required this.id,
    required this.userId,
    required this.name,
    required this.expiresAt,
    required this.revokedAt,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String name;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final DateTime createdAt;

  bool get isRevoked => revokedAt != null;

  bool get isExpired {
    final expiration = expiresAt;
    return expiration != null && !expiration.isAfter(DateTime.now());
  }
}
