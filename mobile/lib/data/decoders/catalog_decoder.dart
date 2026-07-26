import '../models/api_catalog.dart';
import 'decoder_utils.dart';

final class CatalogDecoder {
  const CatalogDecoder();

  /// 将作品响应解码为兼容旧服务端的本地模型。
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
    originalTitle: optionalValue<String>(json, 'original_title') ?? '',
    overview: optionalValue<String>(json, 'overview') ?? '',
    tagline: optionalValue<String>(json, 'tagline') ?? '',
    releaseDate: optionalValue<String>(json, 'release_date') ?? '',
    endDate: optionalValue<String>(json, 'end_date') ?? '',
    certification: optionalValue<String>(json, 'certification') ?? '',
    communityRating: optionalValue<num>(json, 'community_rating')?.toDouble(),
    voteCount: optionalValue<int>(json, 'vote_count') ?? 0,
    genres: _decodeNamedValues(json['genres']),
    countries: _decodeNamedValues(json['countries']),
    studios: _decodeNamedValues(json['studios']),
    credits: _decodeCredits(json['credits']),
    externalIds: _decodeExternalIDs(json['external_ids']),
    metadataStatus: optionalValue<String>(json, 'metadata_status') ?? '',
    metadataRevision: optionalValue<int>(json, 'metadata_revision') ?? 1,
    metadataErrorCode: optionalValue<String>(json, 'metadata_error_code') ?? '',
    provider: optionalValue<String>(json, 'provider') ?? '',
    providerItemId: optionalValue<String>(json, 'provider_item_id') ?? '',
    identityLocked: optionalValue<bool>(json, 'identity_locked') ?? false,
    backdropUrl: optionalValue<String>(json, 'backdrop_url') ?? '',
    favorite: optionalValue<bool>(json, 'favorite') ?? false,
    favoriteRevision: optionalValue<int>(json, 'favorite_revision') ?? 0,
    versions: _decodeVersions(json['versions']),
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

  List<CatalogNamedValue> _decodeNamedValues(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('Expected named value list');
    }
    return value
        .map((item) => objectValue(item, 'catalog named value'))
        .map(
          (item) => CatalogNamedValue(
            id: optionalValue<String>(item, 'id') ?? '',
            name: requiredValue(item, 'name'),
          ),
        )
        .toList(growable: false);
  }

  List<CatalogCredit> _decodeCredits(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('Expected catalog credit list');
    }
    return value
        .map((item) => objectValue(item, 'catalog credit'))
        .map(
          (item) => CatalogCredit(
            personId: optionalValue<String>(item, 'person_id') ?? '',
            name: requiredValue(item, 'name'),
            role: optionalValue<String>(item, 'role') ?? '',
            character: optionalValue<String>(item, 'character') ?? '',
            order: optionalValue<int>(item, 'order') ?? 0,
            profileUrl: optionalValue<String>(item, 'profile_url') ?? '',
          ),
        )
        .toList(growable: false);
  }

  List<CatalogVersion> _decodeVersions(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('Expected catalog version list');
    }
    return value
        .map((item) => objectValue(item, 'catalog version'))
        .map(
          (item) => CatalogVersion(
            mediaId: requiredValue(item, 'media_id'),
            label: optionalValue<String>(item, 'label') ?? '',
            fileSize: optionalValue<int>(item, 'file_size') ?? 0,
            durationMs: optionalValue<int>(item, 'duration_ms'),
            resolution: optionalValue<String>(item, 'resolution') ?? '',
            videoCodec: optionalValue<String>(item, 'video_codec') ?? '',
            audioCodec: optionalValue<String>(item, 'audio_codec') ?? '',
            audioTrackCount: optionalValue<int>(item, 'audio_track_count') ?? 0,
            progressMs: optionalValue<int>(item, 'progress_ms') ?? 0,
            completed: optionalValue<bool>(item, 'completed') ?? false,
            selected: optionalValue<bool>(item, 'selected') ?? false,
          ),
        )
        .toList(growable: false);
  }

  Map<String, String> _decodeExternalIDs(Object? value) {
    if (value == null) return const {};
    if (value is! Map) {
      throw const FormatException('Expected external ID object');
    }
    return Map<String, String>.unmodifiable(
      value.map((key, item) => MapEntry(key.toString(), item.toString())),
    );
  }
}
