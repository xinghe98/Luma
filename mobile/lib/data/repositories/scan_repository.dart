// Scan data boundary used by SettingsController.
import '../models/api_scan.dart';

abstract interface class ScanRepository {
  Future<List<ScanJob>> startAll();

  Future<ScanJob?> latest();

  Future<List<ScanJob>> latestAll();

  Future<ScanJob> get(String id);
}
