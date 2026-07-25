import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/media_item.dart';
import '../../data/models/api_tag.dart';
import '../../data/models/media_filter.dart';
import '../../data/models/media_types.dart';
import '../../data/repositories/media_repository.dart';

enum LoadState { idle, loading, ready, error }

class _MediaBundle {
  const _MediaBundle({
    required this.items,
    required this.continueWatching,
    required this.tags,
  });

  final List<MediaItem> items;
  final List<MediaItem> continueWatching;
  final List<Tag> tags;
}

class MediaController extends ChangeNotifier {
  MediaController(this._repository);

  final MediaRepository _repository;
  static const _maxRememberedItems = 512;
  List<MediaItem> _items = const [];
  List<MediaItem> _continueWatching = const [];
  List<Tag> _tags = const [];

  /// id → 最新 MediaItem，供 O(1) 查找；与 _items / continueWatching 同步维护。
  final Map<String, MediaItem> _byId = {};
  LoadState _loadState = LoadState.idle;
  String? _loadError;
  String? _detailError;
  bool _detailLoading = false;
  int _catalogCount = 0;
  int _loadGeneration = 0;
  int _sessionGeneration = 0;
  // 连接断开后使旧服务器的 mutation 回包和排队操作全部失效。
  int _mutationGeneration = 0;
  final Map<String, Future<void>> _inflight = {};
  Future<void>? _catalogCountRequest;
  bool _disposed = false;

  List<MediaItem> get items => _items;
  List<MediaItem> get continueWatching => _continueWatching;
  List<Tag> get tags => _tags;
  LoadState get loadState => _loadState;
  String? get loadError => _loadError;
  String? get detailError => _detailError;
  bool get detailLoading => _detailLoading;

  /// 媒体库真实总数（分页统计），供设置页展示；首页 items 仅为摘要子集。
  int get catalogCount => _catalogCount;

  MediaItem? findById(String id) => _byId[id];

  void remember(MediaItem item, {bool notify = true}) {
    final changedVisibleItem = _cacheAndReplaceHome(item);
    if (notify && changedVisibleItem) notifyListeners();
  }

  void rememberAll(Iterable<MediaItem> items, {bool notify = true}) {
    var changed = false;
    for (final item in items) {
      final before = _byId[item.id];
      _byId
        ..remove(item.id)
        ..[item.id] = item;
      if (before == null || !identical(before, item)) changed = true;
    }
    if (changed && _items.isNotEmpty) {
      _items = [for (final item in _items) _byId[item.id] ?? item];
    }
    if (changed) _trimRememberedItems();
    if (changed && notify) notifyListeners();
  }

  MediaItem byId(String id) {
    final item = findById(id);
    if (item == null) throw StateError('Unknown media: $id');
    return item;
  }

  Future<void> load() => _runLoad(_loadAll);
  Future<void> refresh() => _runLoad(_refreshAll, showLoading: false);

  Future<_MediaBundle> _loadAll() async {
    final results = await Future.wait<Object>([
      _repository.loadMedia(),
      _repository.loadContinueWatching(),
      _repository.loadTags(),
    ]);
    // 总数异步刷新，不阻塞首页首屏。
    unawaited(refreshCatalogCount());
    return _MediaBundle(
      items: results[0] as List<MediaItem>,
      continueWatching: results[1] as List<MediaItem>,
      tags: results[2] as List<Tag>,
    );
  }

  Future<_MediaBundle> _refreshAll() async {
    final results = await Future.wait<Object>([
      _repository.refresh(),
      _repository.loadContinueWatching(),
      _repository.loadTags(),
    ]);
    unawaited(refreshCatalogCount());
    return _MediaBundle(
      items: results[0] as List<MediaItem>,
      continueWatching: results[1] as List<MediaItem>,
      tags: results[2] as List<Tag>,
    );
  }

  Future<List<MediaItem>> search(MediaFilter filter) =>
      _repository.search(filter);

  Future<MediaListPage> searchPage(MediaFilter filter, {String? cursor}) =>
      _repository.searchPage(filter, cursor: cursor);

  Future<void> refreshCatalogCount() async {
    final pending = _catalogCountRequest;
    if (pending != null) return pending;
    final sessionGeneration = _sessionGeneration;
    late final Future<void> request;
    request = _refreshCatalogCount(sessionGeneration).whenComplete(() {
      if (identical(_catalogCountRequest, request)) {
        _catalogCountRequest = null;
      }
    });
    _catalogCountRequest = request;
    return request;
  }

  Future<void> _refreshCatalogCount(int sessionGeneration) async {
    try {
      final total = await _repository.countMedia();
      if (_disposed || sessionGeneration != _sessionGeneration) return;
      if (_catalogCount == total) return;
      _catalogCount = total;
      notifyListeners();
    } on Object {
      // 统计失败时保留旧值，设置页仍可显示已加载数量。
    }
  }

  Future<void> loadDetail(String id) async {
    final sessionGeneration = _sessionGeneration;
    _detailError = null;
    _detailLoading = true;
    notifyListeners();
    try {
      final item = await _repository.loadDetail(id);
      if (_disposed || sessionGeneration != _sessionGeneration) return;
      _cacheAndReplaceHome(item);
      _detailError = null;
    } on Object catch (error) {
      if (_disposed || sessionGeneration != _sessionGeneration) return;
      _detailError = error.toString();
    } finally {
      if (!_disposed && sessionGeneration == _sessionGeneration) {
        _detailLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _runLoad(
    Future<_MediaBundle> Function() request, {
    bool showLoading = true,
  }) async {
    final generation = ++_loadGeneration;
    if (showLoading) {
      _loadState = LoadState.loading;
      notifyListeners();
    }
    try {
      final bundle = await request();
      if (generation != _loadGeneration) return;
      _items = bundle.items;
      _continueWatching = bundle.continueWatching;
      _tags = bundle.tags;
      _rebuildIndex();
      _loadState = LoadState.ready;
      _loadError = null;
    } on Object catch (error) {
      if (generation != _loadGeneration) return;
      _loadState = LoadState.error;
      _loadError = error.toString();
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) {
    return _runMutation(id, (generation) async {
      final item = findById(id);
      if (item == null) throw StateError('Unknown media: $id');
      final updated = await _repository.setFavorite(id, !item.isFavorite);
      if (generation == _mutationGeneration) _applyUserData(updated);
    });
  }

  Future<void> saveNote(String id, String note) {
    return _runMutation(id, (generation) async {
      final updated = await _repository.saveNote(id, note);
      if (generation == _mutationGeneration) _applyUserData(updated);
    });
  }

  Future<void> updateProgress(String id, int positionMs) {
    return _runMutation(id, (generation) async {
      final updated = await _repository.updateProgress(id, positionMs);
      if (generation == _mutationGeneration) _applyProgress(updated);
    });
  }

  Future<void> _runMutation(
    String id,
    Future<void> Function(int generation) action,
  ) {
    final generation = _mutationGeneration;
    final previous = _inflight[id] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then<void>((_) async {
      // 队列可能在断开后才轮到此操作；此时绝不能请求新服务器。
      if (generation != _mutationGeneration) return;
      await action(generation);
    });
    _inflight[id] = next;
    return next.whenComplete(() {
      if (identical(_inflight[id], next)) _inflight.remove(id);
    });
  }

  void clear() {
    _loadGeneration++;
    _sessionGeneration++;
    _mutationGeneration++;
    _inflight.clear();
    _catalogCountRequest = null;
    // 清除 repository 中按 id 保留的详情，避免换服后复用旧服务器数据。
    if (_repository case SessionResettableMediaRepository resettable) {
      resettable.clearSessionCache();
    }
    _items = const [];
    _continueWatching = const [];
    _tags = const [];
    _byId.clear();
    _catalogCount = 0;
    _loadState = LoadState.idle;
    _loadError = null;
    _detailError = null;
    _detailLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _sessionGeneration++;
    _mutationGeneration++;
    super.dispose();
  }

  void _applyUserData(MediaItem updated) {
    _cacheAndReplaceHome(updated);
    _syncContinueWatchingItem(updated);
    notifyListeners();
  }

  void _applyProgress(MediaItem updated) {
    _cacheAndReplaceHome(updated);
    final continueIndex = _continueWatching.indexWhere(
      (item) => item.id == updated.id,
    );
    if (updated.watchStatus == WatchStatus.watching) {
      if (continueIndex < 0) {
        _continueWatching = [updated, ..._continueWatching];
      } else {
        _continueWatching = [..._continueWatching]..[continueIndex] = updated;
      }
    } else if (continueIndex >= 0) {
      _continueWatching = [..._continueWatching]..removeAt(continueIndex);
    }
    notifyListeners();
  }

  bool _cacheAndReplaceHome(MediaItem updated) {
    final index = _items.indexWhere((item) => item.id == updated.id);
    final changedHomeItem =
        index >= 0 && !identical(_items[index], updated);
    if (changedHomeItem) {
      _items = [..._items]..[index] = updated;
    }
    if (identical(_byId[updated.id], updated)) return changedHomeItem;
    _byId
      ..remove(updated.id)
      ..[updated.id] = updated;
    _trimRememberedItems();
    return changedHomeItem;
  }

  void _syncContinueWatchingItem(MediaItem updated) {
    final continueIndex = _continueWatching.indexWhere(
      (item) => item.id == updated.id,
    );
    if (continueIndex < 0) return;
    _continueWatching = [..._continueWatching]..[continueIndex] = updated;
    _byId
      ..remove(updated.id)
      ..[updated.id] = updated;
    _trimRememberedItems();
  }

  void _rebuildIndex() {
    _byId
      ..clear()
      ..addEntries(_continueWatching.map((item) => MapEntry(item.id, item)))
      ..addEntries(_items.map((item) => MapEntry(item.id, item)));
  }

  void _trimRememberedItems() {
    if (_byId.length <= _maxRememberedItems) return;
    final visible = {
      for (final item in _items) item.id,
      for (final item in _continueWatching) item.id,
    };
    while (_byId.length > _maxRememberedItems) {
      String? discard;
      for (final id in _byId.keys) {
        if (!visible.contains(id)) {
          discard = id;
          break;
        }
      }
      if (discard == null) return;
      _byId.remove(discard);
    }
  }
}
