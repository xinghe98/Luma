// Stores a client-local display alias independently for each server origin.
abstract interface class ServerAliasStore {
  Future<String?> read(String origin);

  Future<void> write(String origin, String alias);

  Future<void> clear(String origin);
}
