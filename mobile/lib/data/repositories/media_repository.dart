import '../models/media_filter.dart';
import '../models/media_item.dart';
import '../models/api_tag.dart';
import '../models/media_types.dart';

abstract interface class MediaRepository {
  Future<List<MediaItem>> loadMedia();
  Future<List<MediaItem>> refresh();
  Future<List<MediaItem>> search(MediaFilter filter);

  /// 单页搜索，供库页无限滚动使用。
  Future<MediaListPage> searchPage(MediaFilter filter, {String? cursor});

  /// 统计符合筛选的媒体总数（分页累加，不入 UI 缓存）。
  Future<int> countMedia({MediaType? type});

  Future<List<MediaItem>> loadContinueWatching();
  Future<List<Tag>> loadTags();
  Future<MediaItem> loadDetail(String id);
  Future<MediaItem> setFavorite(String id, bool value);
  Future<MediaItem> saveNote(String id, String note);
  Future<MediaItem> updateProgress(String id, int positionMs);
}

/// 带本地缓存的实现可在切换服务器时清除旧会话数据。
abstract interface class SessionResettableMediaRepository {
  void clearSessionCache();
}
