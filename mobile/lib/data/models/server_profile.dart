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
  );
}
