import 'package:flutter/foundation.dart';

import '../../data/models/media_filter.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';
import '../../app/controllers/media_controller.dart';

class LibraryFilters {
  const LibraryFilters({this.status, this.favoritesOnly = false});

  final WatchStatus? status;
  final bool favoritesOnly;
}

class LibraryController extends ChangeNotifier {
  /// [initialItems] 来自上一级已渲染的分区并会限制为最多 12 条；[pageSize] 控制远程分页。
  LibraryController({
    MediaType? fixedType,
    String? fixedLibraryKind,
    MediaController? media,
    List<MediaItem> initialItems = const [],
    int pageSize = 48,
  }) : _media = media,
       _fixedType = fixedType,
       _fixedLibraryKind = fixedLibraryKind,
       assert(pageSize >= 1 && pageSize <= 100),
       _pageSize = pageSize,
       _type = fixedType {
    _media?.addListener(_onMediaChanged);
    if (media != null || initialItems.isNotEmpty) {
      final seed = initialItems.isNotEmpty
          ? initialItems
                .take(pageSize < 12 ? pageSize : 12)
                .toList(growable: false)
          : filterMediaItems(
              media!.items,
              _filter,
            ).take(pageSize < 12 ? pageSize : 12).toList(growable: false);
      _remoteItems = seed;
      _visibleItems = seed;
      _remoteIds.addAll(seed.map((item) => item.id));
    }
  }

  final MediaController? _media;
  final int _pageSize;

  /// 固定类型时（如底部导航拆分的影音库/图片库），清除筛选会回到该类型。
  final MediaType? _fixedType;
  final String? _fixedLibraryKind;
  MediaType? _type;
  WatchStatus? _status;
  bool _favoritesOnly = false;
  MediaSort _sort = MediaSort.newest;
  List<MediaItem> _remoteItems = const [];
  final Set<String> _remoteIds = {};
  List<MediaItem> _visibleItems = const [];
  LoadState _loadState = LoadState.ready;
  int _requestGeneration = 0;
  String? _nextCursor;
  bool _loadingMore = false;
  bool _loadMoreError = false;
  bool _started = false;
  bool _disposed = false;

  MediaType? get type => _type;
  WatchStatus? get status => _status;
  bool get favoritesOnly => _favoritesOnly;
  MediaSort get sort => _sort;
  bool get hasExtraFilters => _status != null || _favoritesOnly;
  LibraryFilters get filters =>
      LibraryFilters(status: _status, favoritesOnly: _favoritesOnly);
  LoadState get loadState => _loadState;
  bool get hasMore => _nextCursor != null;
  bool get isLoadingMore => _loadingMore;

  /// 最近一次追加分页是否失败；已有条目和游标会保留供显式重试。
  bool get hasLoadMoreError => _loadMoreError;
  bool get hasStarted => _started;
  int get itemCount => _remoteItems.length;

  /// 是否正在刷新且已有列表（用于保留网格、避免骨架屏拆掉缩略图）。
  bool get isRefreshing =>
      _loadState == LoadState.loading && _visibleItems.isNotEmpty;

  MediaFilter get _filter => MediaFilter(
    type: _type,
    libraryKind: _fixedLibraryKind,
    watchStatus: _status,
    favoritesOnly: _favoritesOnly,
    sort: _sort,
  );

  /// 首次进入库页时拉取第一页。
  Future<void> ensureLoaded() {
    if (_started) return Future.value();
    _started = true;
    return _reload();
  }

  /// 立即进入加载态，但等待 [gate] 完成后才请求第一页，避免与页面转场争用帧预算。
  Future<void> ensureLoadedAfter(Future<void> gate) async {
    if (_started) return;
    _started = true;
    _loadState = LoadState.loading;
    notifyListeners();
    await gate;
    if (_disposed) return;
    await _reload();
  }

  /// [items] 仅在尚未启动远程分页时用于本地筛选（测试/兜底）。
  List<MediaItem> visibleItems([List<MediaItem>? items]) {
    if (_started) return _visibleItems;
    return filterMediaItems(items ?? _media?.items ?? const [], _filter);
  }

  /// 替换媒体类型并重新加载；失败时不继续展示上一类型的结果。
  void setType(MediaType? value) {
    if (_type == value) return;
    _type = value;
    _reload(replaceCriteria: true);
  }

  /// 替换排序条件并重新加载；已有分页状态会被清除。
  void setSort(MediaSort value) {
    if (_sort == value) return;
    _sort = value;
    _reload(replaceCriteria: true);
  }

  /// 应用观看和收藏筛选；条件变化时旧条件结果立即退出当前列表。
  void applyFilters(LibraryFilters value) {
    final changed =
        _status != value.status || _favoritesOnly != value.favoritesOnly;
    _status = value.status;
    _favoritesOnly = value.favoritesOnly;
    _reload(replaceCriteria: changed);
  }

  /// 清除附加筛选，可同时恢复固定媒体类型；随后重新加载当前条件。
  void clearFilters({bool includeType = false}) {
    final previousType = _type;
    final hadFilters = _status != null || _favoritesOnly;
    if (includeType) _type = _fixedType;
    _status = null;
    _favoritesOnly = false;
    _reload(
      replaceCriteria: hadFilters || (includeType && previousType != _type),
    );
  }

  /// 刷新相同条件，并在请求失败时保留已成功加载的内容。
  Future<void> refresh() => _reload();

  /// 追加服务端游标指向的下一页；失败时仅更新局部错误状态。
  Future<void> loadMore() async {
    final media = _media;
    final cursor = _nextCursor;
    if (media == null || cursor == null || _loadingMore) return;
    if (_loadState == LoadState.loading) return;
    final generation = _requestGeneration;
    _loadingMore = true;
    _loadMoreError = false;
    notifyListeners();
    try {
      final page = await media.searchPage(
        _filter,
        cursor: cursor,
        limit: _pageSize,
      );
      if (_disposed || generation != _requestGeneration) return;
      final appended = [
        ..._remoteItems,
        ...page.items.where((item) => _remoteIds.add(item.id)),
      ];
      _remoteItems = appended;
      _nextCursor = page.nextCursor;
      _rebuildVisible();
      _loadingMore = false;
      notifyListeners();
    } on Object {
      if (!_disposed && generation == _requestGeneration) {
        _loadingMore = false;
        _loadMoreError = true;
        notifyListeners();
      }
    }
  }

  Future<void> _reload({bool replaceCriteria = false}) async {
    final media = _media;
    if (media == null) return;
    final generation = ++_requestGeneration;
    _loadState = LoadState.loading;
    _loadingMore = false;
    _loadMoreError = false;
    _nextCursor = null;
    if (replaceCriteria) {
      _remoteItems = const [];
      _remoteIds.clear();
      _visibleItems = const [];
    }
    notifyListeners();
    try {
      final page = await media.searchPage(_filter, limit: _pageSize);
      if (_disposed || generation != _requestGeneration) return;
      _remoteItems = page.items;
      _remoteIds
        ..clear()
        ..addAll(page.items.map((item) => item.id));
      _nextCursor = page.nextCursor;
      _loadState = LoadState.ready;
      _rebuildVisible();
    } on Object {
      if (_disposed || generation != _requestGeneration) return;
      _loadState = LoadState.error;
    }
    notifyListeners();
  }

  void _onMediaChanged() {
    if (_disposed || !_started || _remoteItems.isEmpty) return;
    if (_rebuildVisible()) notifyListeners();
  }

  /// 合并 MediaController 的最新用户字段，并重新应用会随用户操作变化的筛选。
  bool _rebuildVisible() {
    final media = _media;
    final merged = media == null
        ? _remoteItems
        : [for (final item in _remoteItems) media.findById(item.id) ?? item];
    final next = merged
        .where(
          (item) =>
              (_status == null || item.watchStatus == _status) &&
              (!_favoritesOnly || item.isFavorite),
        )
        .toList(growable: false);
    if (_sameItems(_visibleItems, next)) return false;
    _visibleItems = next;
    return true;
  }

  static bool _sameItems(List<MediaItem> a, List<MediaItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    _media?.removeListener(_onMediaChanged);
    super.dispose();
  }
}
