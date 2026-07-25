import 'api_tag.dart';

final class MediaUserData {
  const MediaUserData({
    required this.mediaId,
    required this.customTitle,
    required this.favorite,
    required this.notes,
    required this.progressMs,
    required this.completed,
    required this.lastPlayedAt,
    required this.tags,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  final String mediaId;
  final String? customTitle;
  final bool favorite;
  final String? notes;
  final int progressMs;
  final bool completed;
  final DateTime? lastPlayedAt;
  final List<Tag> tags;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}
