// Storage contract for the active server origin and bearer token.
final class StoredCredentials {
  const StoredCredentials({required this.origin, required this.token});

  final String origin;
  final String? token;
}

abstract interface class CredentialStore {
  Future<StoredCredentials?> read();

  Future<void> write(StoredCredentials credentials);

  Future<void> clear();
}
