/// 已保存的会话只包含可撤销的会话凭据，绝不保存用户密码。
final class StoredCredentials {
  const StoredCredentials({required this.origin, required this.sessionToken});

  final String origin;
  final String? sessionToken;
}

abstract interface class CredentialStore {
  Future<StoredCredentials?> read();

  Future<void> write(StoredCredentials credentials);

  Future<void> clear();
}
