import 'media_types.dart';

class MediaSummary {
  const MediaSummary({
    required this.id,
    required this.title,
    required this.filename,
    required this.mediaType,
    required this.libraryKind,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.thumbnailUrl,
    this.cardThumbnailUrl = '',
    required this.streamUrl,
    required this.originalUrl,
    required this.favorite,
    required this.progressMs,
    required this.completed,
    required this.lastPlayedAt,
    required this.userDataRevision,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String filename;
  final MediaType mediaType;
  final String libraryKind;
  final int? durationMs;
  final int? width;
  final int? height;
  final String thumbnailUrl;
  final String cardThumbnailUrl;
  final String? streamUrl;
  final String? originalUrl;
  final bool favorite;
  final int progressMs;
  final bool completed;
  final DateTime? lastPlayedAt;
  final int userDataRevision;
  final String status;
  final DateTime createdAt;
}

final class MediaDetail extends MediaSummary {
  const MediaDetail({
    required super.id,
    required super.title,
    required super.filename,
    required super.mediaType,
    required super.libraryKind,
    required super.durationMs,
    required super.width,
    required super.height,
    required super.thumbnailUrl,
    super.cardThumbnailUrl,
    required super.streamUrl,
    required super.originalUrl,
    required super.favorite,
    required super.progressMs,
    required super.completed,
    required super.lastPlayedAt,
    required super.userDataRevision,
    required super.status,
    required super.createdAt,
    required this.sourceId,
    required this.mimeType,
    required this.fileSize,
    required this.videoCodec,
    required this.audioCodec,
    required this.container,
    required this.bitrate,
    required this.frameRateNum,
    required this.frameRateDen,
    required this.audioTrackCount,
    required this.orientation,
    required this.capturedAt,
    required this.indexedAt,
  });

  final String sourceId;
  final String mimeType;
  final int fileSize;
  final String videoCodec;
  final String audioCodec;
  final String container;
  final int bitrate;
  final int? frameRateNum;
  final int? frameRateDen;
  final int? audioTrackCount;
  final int? orientation;
  final DateTime? capturedAt;
  final DateTime? indexedAt;
}

final class MediaPage {
  const MediaPage({required this.items, required this.nextCursor});

  final List<MediaSummary> items;
  final String? nextCursor;
}
