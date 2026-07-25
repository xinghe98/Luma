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
    this.metadata = const MetadataSummary.completed(),
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
  final MetadataSummary metadata;
}

final class MetadataSummary {
  const MetadataSummary({
    required this.status,
    required this.total,
    required this.pending,
    required this.refreshing,
    required this.ready,
    required this.unmatched,
    required this.failed,
  });

  const MetadataSummary.waiting()
    : status = 'waiting',
      total = 0,
      pending = 0,
      refreshing = 0,
      ready = 0,
      unmatched = 0,
      failed = 0;

  const MetadataSummary.completed()
    : status = 'completed',
      total = 0,
      pending = 0,
      refreshing = 0,
      ready = 0,
      unmatched = 0,
      failed = 0;

  final String status;
  final int total;
  final int pending;
  final int refreshing;
  final int ready;
  final int unmatched;
  final int failed;
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
