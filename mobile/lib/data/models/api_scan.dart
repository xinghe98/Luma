final class ScanJob {
  const ScanJob({
    required this.id,
    required this.sourceId,
    required this.status,
    required this.phase,
    required this.discoveredCount,
    required this.processedCount,
    required this.failedCount,
    required this.startedAt,
    required this.finishedAt,
    required this.errorCode,
    required this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.processing,
  });

  final String id;
  final String sourceId;
  final String status;
  final String phase;
  final int discoveredCount;
  final int processedCount;
  final int failedCount;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? errorCode;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProcessingSummary processing;
}

final class ProcessingSummary {
  const ProcessingSummary({
    required this.status,
    required this.total,
    required this.discovered,
    required this.probing,
    required this.thumbnailing,
    required this.ready,
    required this.failed,
  });

  final String status;
  final int total;
  final int discovered;
  final int probing;
  final int thumbnailing;
  final int ready;
  final int failed;
}
