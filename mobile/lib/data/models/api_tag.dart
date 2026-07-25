final class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.usageCount,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int usageCount;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;
}
