class ServerProfile {
  const ServerProfile({
    required this.name,
    required this.address,
    required this.token,
    required this.hostName,
    this.sourceCount = 0,
    this.version,
    this.platform,
    this.architecture,
    this.database,
    this.userId,
    this.userRole = 'admin',
    this.capabilities = const [],
  });

  final String name;
  final String address;
  final String token;
  final String hostName;
  final int sourceCount;
  final String? version;
  final String? platform;
  final String? architecture;
  final String? database;
  final String userRole;
  final List<String> capabilities;

  /// 已认证账号的服务端用户 id；由 /system/info 或登录响应带出，
  /// 会话恢复后同样有效。为 null 时不得用作身份/记忆键。
  final String? userId;

  bool can(String capability) =>
      capabilities.isEmpty || capabilities.contains(capability);

  ServerProfile copyWith({String? name}) => ServerProfile(
    name: name ?? this.name,
    address: address,
    token: token,
    hostName: hostName,
    sourceCount: sourceCount,
    version: version,
    platform: platform,
    architecture: architecture,
    database: database,
    userId: userId,
    userRole: userRole,
    capabilities: capabilities,
  );
}
