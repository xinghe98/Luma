import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/models/api_tag.dart';
import '../../data/models/media_filter.dart';
import '../../data/models/media_item.dart';
import '../../data/models/media_types.dart';

class SearchController extends ChangeNotifier {
  SearchController(this._media) {
    _tags = _media.tags;
    _media.addListener(_onMediaChanged);
  }

  final MediaController _media;
  final List<String> _recent = [];
  String _query = '';
  MediaType? _type;
  String? _tag;
  String? _tagId;
  List<MediaItem> _results = const [];
  List<Tag> _tags = const [];
  Timer? _debounce;
  int _requestVersion = 0;
  LoadState _loadState = LoadState.ready;
  bool _disposed = false;
  String? _nextCursor;
  bool _loadingMore = false;
  bool _loadMoreError = false;

  List<String> get recent => List.unmodifiable(_recent);
  String get query => _query;
  MediaType? get type => _type;
  String? get tag => _tag;
  String? get tagId => _tagId;
  List<Tag> get tags => _tags;
  LoadState get loadState => _loadState;

  /// 当前搜索是否还有服务端游标可继续加载。
  bool get hasMore => _nextCursor != null;

  /// 是否正在追加搜索结果下一页。
  bool get isLoadingMore => _loadingMore;

  /// 最近一次追加是否失败；已有搜索结果会继续保留。
  bool get hasLoadMoreError => _loadMoreError;
  bool get hasCriteria =>
      _query.trim().isNotEmpty || _type != null || _tag != null;

  /// 仅在有搜索条件时返回结果；无条件为空，避免首屏铺全库网格。
  List<MediaItem> get results => hasCriteria ? _results : const [];

  void setQuery(String value) {
    _query = value;
    notifyListeners();
    _scheduleSearch();
  }

  void setType(MediaType? value) {
    _type = value;
    notifyListeners();
    _scheduleSearch(immediate: true);
  }

  void toggleTag(String id, String name) {
    final selected = _tagId == id;
    _tagId = selected ? null : id;
    _tag = selected ? null : name;
    notifyListeners();
    _scheduleSearch(immediate: true);
  }

  void remember(String value) {
    final term = value.trim();
    if (term.isEmpty) return;
    _recent.remove(term);
    _recent.insert(0, term);
    if (_recent.length > 5) _recent.removeLast();
    notifyListeners();
  }

  void clearRecent() {
    _recent.clear();
    notifyListeners();
  }

  void clearCriteria() {
    _debounce?.cancel();
    _query = '';
    _type = null;
    _tag = null;
    _tagId = null;
    _results = const [];
    _nextCursor = null;
    _loadingMore = false;
    _loadMoreError = false;
    _requestVersion++;
    _loadState = LoadState.ready;
    notifyListeners();
  }

  void _scheduleSearch({bool immediate = false}) {
    _debounce?.cancel();
    final version = ++_requestVersion;
    if (!hasCriteria) {
      _results = const [];
      _nextCursor = null;
      _loadingMore = false;
      _loadMoreError = false;
      _loadState = LoadState.ready;
      notifyListeners();
      return;
    }
    _loadState = LoadState.loading;
    _nextCursor = null;
    _loadingMore = false;
    _loadMoreError = false;
    notifyListeners();
    // 快照筛选条件，避免旧 timer 在清空后意外发起无条件全库搜索。
    final filter = MediaFilter(
      text: _query,
      type: _type,
      tag: _tag,
      tagId: _tagId,
    );
    _debounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 300),
      () => _search(version, filter),
    );
  }

  Future<void> _search(int version, MediaFilter filter) async {
    try {
      // 与媒体库共用分页 API，搜索首屏只取一页，避免输入一次就拉完整个库。
      final results = await _media.searchPage(filter);
      if (_disposed || version != _requestVersion) return;
      _results = results.items;
      _nextCursor = results.nextCursor;
      _loadState = LoadState.ready;
    } on Object {
      if (_disposed || version != _requestVersion) return;
      _loadState = LoadState.error;
    }
    if (!_disposed) notifyListeners();
  }

  void retry() => _scheduleSearch(immediate: true);

  /// 使用当前条件和服务端游标追加下一页；失败时保留已有结果供用户重试。
  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingMore || _loadState == LoadState.loading) {
      return;
    }
    final version = _requestVersion;
    _loadingMore = true;
    _loadMoreError = false;
    notifyListeners();
    try {
      final page = await _media.searchPage(
        MediaFilter(text: _query, type: _type, tag: _tag, tagId: _tagId),
        cursor: cursor,
      );
      if (_disposed || version != _requestVersion) return;
      final ids = _results.map((item) => item.id).toSet();
      _results = [..._results, ...page.items.where((item) => ids.add(item.id))];
      _nextCursor = page.nextCursor;
      _loadingMore = false;
      notifyListeners();
    } on Object {
      if (_disposed || version != _requestVersion) return;
      _loadingMore = false;
      _loadMoreError = true;
      notifyListeners();
    }
  }

  void _onMediaChanged() {
    if (_disposed) return;
    var changed = false;
    final nextTags = _media.tags;
    if (!identical(nextTags, _tags)) {
      _tags = nextTags;
      changed = true;
    }
    final nextResults = [
      for (final item in _results) _media.findById(item.id) ?? item,
    ];
    if (!_sameItems(_results, nextResults)) {
      _results = nextResults;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  static bool _sameItems(List<MediaItem> left, List<MediaItem> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!identical(left[index], right[index])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _requestVersion++;
    _debounce?.cancel();
    _media.removeListener(_onMediaChanged);
    super.dispose();
  }
}
