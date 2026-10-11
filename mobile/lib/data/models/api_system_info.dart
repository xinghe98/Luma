final class SystemInfo {
  const SystemInfo({
    required this.version,
    required this.platform,
    required this.architecture,
    required this.database,
    this.userId,
    this.userRole = 'admin',
    this.capabilities = const [],
  });

  final String version;
  final String platform;
  final String architecture;
  final String database;

  /// 当前已认证账号的服务端用户 id；恢复会话时同样来自 /system/info。
  /// 为 null 表示后端版本未返回 user.id，调用方不得把它当身份键。
  final String? userId;
  final String userRole;
  final List<String> capabilities;
}
