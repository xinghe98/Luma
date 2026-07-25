import '../models/api_source.dart';
import '../models/api_managed_source.dart';

abstract interface class SourceRepository {
  Future<List<Source>> list({bool refresh = false});

  Future<Source?> find(String id);
}

abstract interface class MutableSourceRepository implements SourceRepository {
  Future<Source> updateLibraryKind(String id, String libraryKind);

  Future<List<String>> listAvailableRoots();

  Future<ManagedSourceCreation> createManagedSource({
    required String name,
    required String rootPath,
    required String libraryKind,
    required List<String> userIds,
  });
}

abstract interface class SessionSeedableSourceRepository {
  void seedSessionCache(List<Source> sources);
}

abstract interface class SessionResettableSourceRepository {
  void clearSessionCache();
}
