import 'api_scan.dart';
import 'api_source.dart';

final class ManagedSourceCreation {
  const ManagedSourceCreation({required this.source, required this.scanJob});

  final Source source;
  final ScanJob scanJob;
}
