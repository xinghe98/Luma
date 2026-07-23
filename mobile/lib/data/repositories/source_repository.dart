// Shared source catalog used by connection, details, and scan workflows.
import '../models/api_source.dart';
import '../models/api_managed_source.dart';

abstract interface class SourceRepository {
  Future<List<Source>> list({bool refresh = false});

  Future<Source?> find(String id);
}

abstract interface class MutableSourceRepository implements SourceRepository {
  Future<Source> updateLibraryKind(String id, String libraryKind);

  /// Creates a server-local source, grants selected members and starts its scan.
  Future<ManagedSourceCreation> createManagedSource({
    required String name,
    required String rootPath,
    required String libraryKind,
    required List<String> userIds,
  });
}

/// Lets connection/session code replace a cache using data fetched through an
/// isolated candidate client, without issuing a second shared-session request.
abstract interface class SessionSeedableSourceRepository {
  void seedSessionCache(List<Source> sources);
}

abstract interface class SessionResettableSourceRepository {
  void clearSessionCache();
}
