import 'media_types.dart';

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.type,
    required this.duration,
    required this.resolution,
    required this.format,
    required this.fileSize,
    required this.directory,
    required this.tags,
    required this.addedAt,
    required this.artSeed,
    this.aspectRatio = 16 / 9,
    this.isFavorite = false,
    this.progress = 0,
    this.note = '',
    this.filename = '',
    this.thumbnailUrl = '',
    this.cardThumbnailUrl = '',
    this.streamUrl,
    this.originalUrl,
    this.mimeType = '',
    this.sourceId = '',
    this.sourceName = '',
    this.libraryKind = 'personal',
    this.videoCodec = '',
    this.audioCodec = '',
    this.bitrate = 0,
    this.userDataRevision = 0,
    this.completed = false,
    this.lastPlayedAt,
    this.status = 'ready',
  });

  final String id;
  final String title;
  final MediaType type;
  final Duration duration;
  final String resolution;
  final String format;
  final String fileSize;
  final String directory;
  final List<String> tags;
  final DateTime addedAt;
  final int artSeed;
  final double aspectRatio;
  final bool isFavorite;
  final double progress;
  final String note;
  final String filename;
  final String thumbnailUrl;
  final String cardThumbnailUrl;
  final String? streamUrl;
  final String? originalUrl;
  final String mimeType;
  final String sourceId;
  final String sourceName;
  final String libraryKind;
  final String videoCodec;
  final String audioCodec;
  final int bitrate;
  final int userDataRevision;
  final bool completed;
  final DateTime? lastPlayedAt;
  final String status;

  bool get isPortrait => aspectRatio < 1;
  WatchStatus get watchStatus => progress <= 0
      ? WatchStatus.unwatched
      : completed || progress >= 0.9
      ? WatchStatus.watched
      : WatchStatus.watching;

  MediaItem copyWith({
    String? title,
    Duration? duration,
    String? resolution,
    String? format,
    String? fileSize,
    String? directory,
    List<String>? tags,
    DateTime? addedAt,
    double? aspectRatio,
    bool? isFavorite,
    double? progress,
    String? note,
    String? filename,
    String? thumbnailUrl,
    String? cardThumbnailUrl,
    String? streamUrl,
    String? originalUrl,
    String? mimeType,
    String? sourceId,
    String? sourceName,
    String? libraryKind,
    String? videoCodec,
    String? audioCodec,
    int? bitrate,
    int? userDataRevision,
    bool? completed,
    DateTime? lastPlayedAt,
    bool clearLastPlayedAt = false,
    String? status,
  }) {
    return MediaItem(
      id: id,
      title: title ?? this.title,
      type: type,
      duration: duration ?? this.duration,
      resolution: resolution ?? this.resolution,
      format: format ?? this.format,
      fileSize: fileSize ?? this.fileSize,
      directory: directory ?? this.directory,
      tags: tags ?? this.tags,
      addedAt: addedAt ?? this.addedAt,
      artSeed: artSeed,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      isFavorite: isFavorite ?? this.isFavorite,
      progress: progress ?? this.progress,
      note: note ?? this.note,
      filename: filename ?? this.filename,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      cardThumbnailUrl: cardThumbnailUrl ?? this.cardThumbnailUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      originalUrl: originalUrl ?? this.originalUrl,
      mimeType: mimeType ?? this.mimeType,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      libraryKind: libraryKind ?? this.libraryKind,
      videoCodec: videoCodec ?? this.videoCodec,
      audioCodec: audioCodec ?? this.audioCodec,
      bitrate: bitrate ?? this.bitrate,
      userDataRevision: userDataRevision ?? this.userDataRevision,
      completed: completed ?? this.completed,
      lastPlayedAt: clearLastPlayedAt
          ? null
          : (lastPlayedAt ?? this.lastPlayedAt),
      status: status ?? this.status,
    );
  }
}
