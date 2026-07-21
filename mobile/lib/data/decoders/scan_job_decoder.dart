// Decodes scan jobs and their nested processing summary.
import '../models/api_scan.dart';
import 'decoder_utils.dart';

final class ScanJobDecoder {
  const ScanJobDecoder();

  ScanJob decode(Map<String, dynamic> json) {
    return ScanJob(
      id: requiredValue(json, 'id'),
      sourceId: requiredValue(json, 'source_id'),
      status: requiredValue(json, 'status'),
      phase: requiredValue(json, 'phase'),
      discoveredCount: requiredValue(json, 'discovered_count'),
      processedCount: requiredValue(json, 'processed_count'),
      failedCount: requiredValue(json, 'failed_count'),
      startedAt: optionalDate(json, 'started_at'),
      finishedAt: optionalDate(json, 'finished_at'),
      errorCode: optionalValue(json, 'error_code'),
      errorMessage: optionalValue(json, 'error_message'),
      createdAt: requiredDate(json, 'created_at'),
      updatedAt: requiredDate(json, 'updated_at'),
      processing: _decodeProcessing(
        objectValue(json['processing'], 'processing'),
      ),
    );
  }

  ProcessingSummary _decodeProcessing(Map<String, dynamic> json) {
    return ProcessingSummary(
      status: requiredValue(json, 'status'),
      total: requiredValue(json, 'total'),
      discovered: requiredValue(json, 'discovered'),
      probing: requiredValue(json, 'probing'),
      thumbnailing: requiredValue(json, 'thumbnailing'),
      ready: requiredValue(json, 'ready'),
      failed: requiredValue(json, 'failed'),
    );
  }
}
