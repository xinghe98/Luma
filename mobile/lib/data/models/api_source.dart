// Typed representation of a configured backend media source.
final class Source {
  const Source({
    required this.id,
    required this.name,
    required this.type,
    required this.libraryKind,
    required this.enabled,
    required this.status,
    required this.lastScanId,
    required this.lastSeenAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String type;
  final String libraryKind;
  final bool enabled;
  final String status;
  final String? lastScanId;
  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}
