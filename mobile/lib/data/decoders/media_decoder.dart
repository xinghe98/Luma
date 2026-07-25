import '../models/api_media.dart';
import '../models/media_types.dart';
import 'decoder_utils.dart';

final class MediaDecoder {
  const MediaDecoder();

  MediaSummary decodeSummary(Map<String, dynamic> json) {
    return MediaSummary(
      id: requiredValue(json, 'id'),
      title: requiredValue(json, 'title'),
      filename: requiredValue(json, 'filename'),
      mediaType: _mediaType(requiredValue(json, 'media_type')),
      libraryKind: optionalValue<String>(json, 'library_kind') ?? 'personal',
      catalogItemId: optionalValue<String>(json, 'catalog_item_id'),
      durationMs: nullableValue(json, 'duration_ms'),
      width: nullableValue(json, 'width'),
      height: nullableValue(json, 'height'),
      thumbnailUrl: requiredValue(json, 'thumbnail_url'),
      cardThumbnailUrl: optionalValue<String>(json, 'card_thumbnail_url') ?? '',
      streamUrl: nullableValue(json, 'stream_url'),
      originalUrl: nullableValue(json, 'original_url'),
      favorite: requiredValue(json, 'favorite'),
      progressMs: requiredValue(json, 'progress_ms'),
      completed: requiredValue(json, 'completed'),
      lastPlayedAt: nullableDate(json, 'last_played_at'),
      userDataRevision: requiredValue(json, 'user_data_revision'),
      status: requiredValue(json, 'status'),
      createdAt: requiredDate(json, 'created_at'),
    );
  }

  MediaDetail decodeDetail(Map<String, dynamic> json) {
    final summary = decodeSummary(json);
    return MediaDetail(
      id: summary.id,
      title: summary.title,
      filename: summary.filename,
      mediaType: summary.mediaType,
      libraryKind: summary.libraryKind,
      catalogItemId: summary.catalogItemId,
      durationMs: summary.durationMs,
      width: summary.width,
      height: summary.height,
      thumbnailUrl: summary.thumbnailUrl,
      cardThumbnailUrl: summary.cardThumbnailUrl,
      streamUrl: summary.streamUrl,
      originalUrl: summary.originalUrl,
      favorite: summary.favorite,
      progressMs: summary.progressMs,
      completed: summary.completed,
      lastPlayedAt: summary.lastPlayedAt,
      userDataRevision: summary.userDataRevision,
      status: summary.status,
      createdAt: summary.createdAt,
      sourceId: requiredValue(json, 'source_id'),
      mimeType: requiredValue(json, 'mime_type'),
      fileSize: requiredValue(json, 'file_size'),
      videoCodec: requiredValue(json, 'video_codec'),
      audioCodec: requiredValue(json, 'audio_codec'),
      container: requiredValue(json, 'container'),
      bitrate: requiredValue(json, 'bitrate'),
      frameRateNum: nullableValue(json, 'frame_rate_num'),
      frameRateDen: nullableValue(json, 'frame_rate_den'),
      audioTrackCount: nullableValue(json, 'audio_track_count'),
      orientation: nullableValue(json, 'orientation'),
      capturedAt: nullableDate(json, 'captured_at'),
      indexedAt: nullableDate(json, 'indexed_at'),
    );
  }

  MediaPage decodePage(Map<String, dynamic> json) {
    return MediaPage(
      items: listValue(json, 'items')
          .map((item) => decodeSummary(objectValue(item, 'media item')))
          .toList(growable: false),
      nextCursor: nullableValue(json, 'next_cursor'),
    );
  }

  MediaType _mediaType(String value) => switch (value) {
    'video' => MediaType.video,
    'image' => MediaType.image,
    _ => throw FormatException('Unknown media_type: $value'),
  };
}
