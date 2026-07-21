// Shared source catalog used by connection, details, and scan workflows.
import '../models/api_source.dart';

abstract interface class SourceRepository {
  Future<List<Source>> list({bool refresh = false});

  Future<Source?> find(String id);
}
