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
  LibraryController({
    MediaType? fixedType,
    String? fixedLibraryKind,
    MediaController? media,
  }) : _media = media,
       _fixedType = fixedType,
       _fixedLibraryKind = fixedLibraryKind,
       _type = fixedType {
    _media?.addListener(_onMediaChanged);
    if (media != null) {
      final seed = filterMediaItems(
        media.items,
        _filter,
      ).take(12).toList(growable: false);
      _remoteItems = seed;
      _visibleItems = seed;
      _remoteIds.addAll(seed.map((item) => item.id));
    }
  }

  final MediaController? _media;

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

  /// [items] 仅在尚未启动远程分页时用于本地筛选（测试/兜底）。
  List<MediaItem> visibleItems([List<MediaItem>? items]) {
    if (_started) return _visibleItems;
    return filterMediaItems(items ?? _media?.items ?? const [], _filter);
  }

  void setType(MediaType? value) {
    if (_type == value) return;
    _type = value;
    _reload();
  }

  void setSort(MediaSort value) {
    if (_sort == value) return;
    _sort = value;
    _reload();
  }

  void applyFilters(LibraryFilters value) {
    _status = value.status;
    _favoritesOnly = value.favoritesOnly;
    _reload();
  }

  void clearFilters({bool includeType = false}) {
    if (includeType) _type = _fixedType;
    _status = null;
    _favoritesOnly = false;
    _reload();
  }

  Future<void> refresh() => _reload();

  Future<void> loadMore() async {
    final media = _media;
    final cursor = _nextCursor;
    if (media == null || cursor == null || _loadingMore) return;
    if (_loadState == LoadState.loading) return;
    final generation = _requestGeneration;
    _loadingMore = true;
    try {
      final page = await media.searchPage(_filter, cursor: cursor);
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
      // 保留已加载内容，允许用户再次滚动重试。
      if (!_disposed && generation == _requestGeneration) _loadingMore = false;
    }
  }

  Future<void> _reload() async {
    final media = _media;
    if (media == null) return;
    final generation = ++_requestGeneration;
    _loadState = LoadState.loading;
    _loadingMore = false;
    _nextCursor = null;
    notifyListeners();
    try {
      final page = await media.searchPage(_filter);
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

  /// 用 MediaController 中的最新收藏/进度合并远程列表；有变化返回 true。
  bool _rebuildVisible() {
    final media = _media;
    final next = media == null
        ? _remoteItems
        : [for (final item in _remoteItems) media.findById(item.id) ?? item];
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
