enum CatalogKind { movie, series }

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
