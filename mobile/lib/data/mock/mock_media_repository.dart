import '../fixtures/media_fixtures.dart';
import '../models/media_filter.dart';
import '../models/media_item.dart';
import '../models/api_tag.dart';
import '../models/media_types.dart';
import '../repositories/media_repository.dart';

class MockMediaRepository implements MediaRepository {
  MockMediaRepository() : _items = buildMediaFixtures();

  List<MediaItem> _items;
  static const _pageSize = 48;

  @override
  Future<List<MediaItem>> loadMedia() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    return List.unmodifiable(_items);
  }

  @override
  Future<List<MediaItem>> refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 850));
    return List.unmodifiable(_items);
  }

  @override
  Future<List<MediaItem>> search(MediaFilter filter) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return filterMediaItems(_items, filter);
  }

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final all = filterMediaItems(_items, filter);
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + (limit ?? _pageSize)).clamp(0, all.length);
    final slice = all.sublist(start.clamp(0, all.length), end);
    final next = end < all.length ? '$end' : null;
    return MediaListPage(items: slice, nextCursor: next);
  }

  @override
  Future<int> countMedia({MediaType? type}) async {
    if (type == null) return _items.length;
    return _items.where((item) => item.type == type).length;
  }

  @override
  Future<MediaItem> saveNote(String id, String note) =>
      _replace(id, (item) => item.copyWith(note: note));

  @override
  Future<MediaItem> setFavorite(String id, bool value) =>
      _replace(id, (item) => item.copyWith(isFavorite: value));

  @override
  Future<MediaItem> updateProgress(String id, int positionMs) =>
      _replace(id, (item) {
        final total = item.duration.inMilliseconds;
        final safe = positionMs < 0 ? 0 : positionMs;
        final progress = total <= 0 ? 0.0 : (safe / total).clamp(0.0, 1.0);
        final completed = total > 0 && progress >= 0.9;
        return item.copyWith(
          progress: progress,
          completed: completed,
          lastPlayedAt: DateTime.now(),
        );
      });

  @override
  Future<List<MediaItem>> loadContinueWatching() async => _items
      .where((item) => item.watchStatus == WatchStatus.watching)
      .toList(growable: false);

  @override
  Future<List<Tag>> loadTags() async => const [];

  @override
  Future<MediaItem> loadDetail(String id) async =>
      _items.firstWhere((item) => item.id == id);

  Future<MediaItem> _replace(
    String id,
    MediaItem Function(MediaItem item) update,
  ) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Unknown media: $id');
    final updated = update(_items[index]);
    _items = [..._items]..[index] = updated;
    return updated;
  }
}
