import 'api_scan.dart';
import 'api_source.dart';

// Result of the single administrator operation that configures and starts a source.
final class ManagedSourceCreation {
  const ManagedSourceCreation({required this.source, required this.scanJob});

  final Source source;
  final ScanJob scanJob;
}
