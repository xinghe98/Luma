import '../models/api_catalog.dart';
import 'decoder_utils.dart';

final class CatalogDecoder {
  const CatalogDecoder();

  CatalogItem decode(Map<String, dynamic> json) => CatalogItem(
    id: requiredValue(json, 'id'),
    sourceId: requiredValue(json, 'source_id'),
    kind: requiredValue<String>(json, 'kind') == 'series'
        ? CatalogKind.series
        : CatalogKind.movie,
    title: requiredValue(json, 'title'),
    year: optionalValue(json, 'year'),
    mediaCount: requiredValue(json, 'media_count'),
    episodeCount: requiredValue(json, 'episode_count'),
    completedCount: requiredValue(json, 'completed_count'),
    playableMediaId: requiredValue(json, 'playable_media_id'),
    thumbnailUrl: requiredValue(json, 'thumbnail_url'),
    posterUrl:
        optionalValue<String>(json, 'poster_url') ??
        requiredValue(json, 'thumbnail_url'),
    durationMs: optionalValue(json, 'duration_ms'),
    resolution: optionalValue<String>(json, 'resolution') ?? '',
    progressMs: requiredValue(json, 'progress_ms'),
    completed: requiredValue(json, 'completed'),
    updatedAt: requiredDate(json, 'updated_at'),
    episodes: (json['episodes'] as List<Object?>? ?? const [])
        .map((value) => decodeEpisode(objectValue(value, 'episode')))
        .toList(growable: false),
  );

  CatalogEpisode decodeEpisode(Map<String, dynamic> json) => CatalogEpisode(
    id: requiredValue(json, 'id'),
    seasonNumber: requiredValue(json, 'season_number'),
    episodeNumber: requiredValue(json, 'episode_number'),
    title: requiredValue(json, 'title'),
    mediaId: requiredValue(json, 'media_id'),
    durationMs: optionalValue(json, 'duration_ms'),
    resolution: optionalValue<String>(json, 'resolution') ?? '',
    progressMs: requiredValue(json, 'progress_ms'),
    completed: requiredValue(json, 'completed'),
    thumbnailUrl: requiredValue(json, 'thumbnail_url'),
  );

  CatalogIssue decodeIssue(Map<String, dynamic> json) => CatalogIssue(
    mediaId: requiredValue(json, 'media_id'),
    filename: requiredValue(json, 'filename'),
    sourceId: requiredValue(json, 'source_id'),
    libraryKind: requiredValue(json, 'library_kind'),
    suggestedTitle: requiredValue(json, 'suggested_title'),
    seasonNumber: optionalValue(json, 'season_number'),
    episodeNumber: optionalValue(json, 'episode_number'),
  );

  List<CatalogItem> decodeList(Map<String, dynamic> json) => listValue(
    json,
    'items',
  ).map((value) => decode(objectValue(value, 'catalog item'))).toList();

  List<CatalogIssue> decodeIssues(Map<String, dynamic> json) => listValue(
    json,
    'items',
  ).map((value) => decodeIssue(objectValue(value, 'catalog issue'))).toList();
}
