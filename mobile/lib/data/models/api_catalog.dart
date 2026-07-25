enum CatalogKind { movie, series }

/// CatalogNamedValue 表示作品资料中的类型、国家或制作公司等具名条目。
final class CatalogNamedValue {
  const CatalogNamedValue({required this.id, required this.name});

  final String id;
  final String name;
}

/// CatalogCredit 表示作品资料中的单个演员或幕后人员。
final class CatalogCredit {
  const CatalogCredit({
    required this.personId,
    required this.name,
    required this.role,
    required this.character,
    required this.order,
  });

  final String personId;
  final String name;
  final String role;
  final String character;
  final int order;
}

final class CatalogEpisode {
  const CatalogEpisode({
    required this.id,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    required this.mediaId,
    required this.durationMs,
    required this.resolution,
    required this.progressMs,
    required this.completed,
    required this.thumbnailUrl,
  });

  final String id;
  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final String mediaId;
  final int? durationMs;
  final String resolution;
  final int progressMs;
  final bool completed;
  final String thumbnailUrl;
}

/// CatalogItem 表示可播放作品及其可选的刮削资料。
final class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.sourceId,
    required this.kind,
    required this.title,
    required this.year,
    required this.mediaCount,
    required this.episodeCount,
    required this.completedCount,
    required this.playableMediaId,
    required this.thumbnailUrl,
    required this.posterUrl,
    required this.durationMs,
    required this.resolution,
    required this.progressMs,
    required this.completed,
    required this.updatedAt,
    this.episodes = const [],
    this.originalTitle = '',
    this.overview = '',
    this.tagline = '',
    this.releaseDate = '',
    this.endDate = '',
    this.certification = '',
    this.communityRating,
    this.voteCount = 0,
    this.genres = const [],
    this.countries = const [],
    this.studios = const [],
    this.credits = const [],
    this.externalIds = const {},
    this.metadataStatus = '',
    this.metadataRevision = 1,
    this.metadataErrorCode = '',
    this.provider = '',
    this.providerItemId = '',
    this.identityLocked = false,
    this.backdropUrl = '',
  });

  final String id;
  final String sourceId;
  final CatalogKind kind;
  final String title;
  final int? year;
  final int mediaCount;
  final int episodeCount;
  final int completedCount;
  final String playableMediaId;
  final String thumbnailUrl;
  final String posterUrl;
  final int? durationMs;
  final String resolution;
  final int progressMs;
  final bool completed;
  final DateTime updatedAt;
  final List<CatalogEpisode> episodes;
  final String originalTitle;
  final String overview;
  final String tagline;
  final String releaseDate;
  final String endDate;
  final String certification;
  final double? communityRating;
  final int voteCount;
  final List<CatalogNamedValue> genres;
  final List<CatalogNamedValue> countries;
  final List<CatalogNamedValue> studios;
  final List<CatalogCredit> credits;
  final Map<String, String> externalIds;
  final String metadataStatus;
  final int metadataRevision;
  final String metadataErrorCode;
  final String provider;
  final String providerItemId;
  final bool identityLocked;
  final String backdropUrl;

  double get progress => durationMs == null || durationMs == 0
      ? 0
      : (progressMs / durationMs!).clamp(0, 1);
}

final class CatalogIssue {
  const CatalogIssue({
    required this.mediaId,
    required this.filename,
    required this.sourceId,
    required this.libraryKind,
    required this.suggestedTitle,
    required this.seasonNumber,
    required this.episodeNumber,
  });

  final String mediaId;
  final String filename;
  final String sourceId;
  final String libraryKind;
  final String suggestedTitle;
  final int? seasonNumber;
  final int? episodeNumber;
}
