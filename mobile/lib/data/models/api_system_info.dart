// Typed representation of authenticated server information.
final class SystemInfo {
  const SystemInfo({
    required this.version,
    required this.platform,
    required this.architecture,
    required this.database,
    this.userRole = 'admin',
    this.capabilities = const [],
  });

  final String version;
  final String platform;
  final String architecture;
  final String database;
  final String userRole;
  final List<String> capabilities;
}
