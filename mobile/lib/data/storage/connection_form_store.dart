/// 连接页表单记忆：仅保存可回填的服务器定位信息，绝不保存密码。
final class SavedConnectionForm {
  const SavedConnectionForm({
    required this.host,
    required this.port,
    required this.username,
  });

  final String host;
  final String port;
  final String username;

  Map<String, Object?> toJson() => {
    'host': host,
    'port': port,
    'username': username,
  };

  static SavedConnectionForm fromJson(Object? value) {
    if (value is! Map) throw const FormatException('连接表单格式无效');
    final host = value['host'];
    final port = value['port'];
    final username = value['username'];
    if (host is! String ||
        host.isEmpty ||
        port is! String ||
        username is! String) {
      throw const FormatException('连接表单格式无效');
    }
    return SavedConnectionForm(host: host, port: port, username: username);
  }
}

abstract interface class ConnectionFormStore {
  Future<SavedConnectionForm?> read();

  Future<void> write(SavedConnectionForm form);

  Future<void> clear();
}
