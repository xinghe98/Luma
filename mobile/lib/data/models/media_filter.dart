import 'media_item.dart';
import 'media_types.dart';

/// 游标分页的一页媒体结果。
class MediaListPage {
  const MediaListPage({required this.items, required this.nextCursor});

  final List<MediaItem> items;
  final String? nextCursor;
  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

class MediaFilter {
  const MediaFilter({
    this.text = '',
    this.type,
    this.libraryKind,
    this.tag,
    this.tagId,
    this.watchStatus,
    this.favoritesOnly = false,
    this.sort = MediaSort.newest,
  });

  final String text;
  final MediaType? type;
  final String? libraryKind;
  final String? tag;
  final String? tagId;
  final WatchStatus? watchStatus;
  final bool favoritesOnly;
  final MediaSort sort;
}

List<MediaItem> filterMediaItems(List<MediaItem> source, MediaFilter filter) {
  final keyword = filter.text.trim().toLowerCase();
  final results = source.where((item) {
    final matchesText =
        keyword.isEmpty ||
        item.title.toLowerCase().contains(keyword) ||
        item.tags.any((tag) => tag.toLowerCase().contains(keyword));
    return matchesText &&
        (filter.type == null || item.type == filter.type) &&
        (filter.libraryKind == null ||
            item.libraryKind == filter.libraryKind) &&
        (filter.tag == null || item.tags.contains(filter.tag)) &&
        (filter.watchStatus == null ||
            item.watchStatus == filter.watchStatus) &&
        (!filter.favoritesOnly || item.isFavorite);
  }).toList();

  switch (filter.sort) {
    case MediaSort.newest:
      final hasDates = results.any(
        (item) => item.addedAt.millisecondsSinceEpoch != 0,
      );
      if (hasDates) {
        results.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      }
    case MediaSort.title:
      results.sort((a, b) => a.title.compareTo(b.title));
    case MediaSort.duration:
      results.sort((a, b) => b.duration.compareTo(a.duration));
  }
  return results;
}
