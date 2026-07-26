import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/api_catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import 'catalog_store.dart';

enum CatalogLoadState { idle, loading, ready, error }

final class CatalogController extends ChangeNotifier {
  /// 管理单一作品类型的列表请求，并订阅可选的会话级共享 store。
  CatalogController(
    this._repository, {
    required CatalogKind kind,
    List<CatalogItem> initialItems = const [],
  }) : _kind = kind,
       _store = _catalogStore(_repository),
       _items = initialItems,
       _state = initialItems.isEmpty
           ? CatalogLoadState.idle
           : CatalogLoadState.ready {
    _store?.rememberAll(initialItems, notify: false);
    _store?.addListener(_handleStoreChanged);
  }

  final CatalogRepository _repository;
  final CatalogKind _kind;
  final CatalogStore? _store;
  CatalogLoadState _state;
  List<CatalogItem> _items;
  String? _error;
  int _generation = 0;
  bool _disposed = false;
  bool _started = false;
  Future<void>? _inflight;

  CatalogKind get kind => _kind;
  CatalogLoadState get state => _state;
  List<CatalogItem> get items => _items;
  String? get error => _error;
  bool get hasStarted => _started;

  Future<void> ensureLoaded() {
    if (_started) return _inflight ?? Future.value();
    return load();
  }

  /// 立即显示加载状态，但等待 [gate] 完成后才刷新完整作品列表。
  Future<void> ensureLoadedAfter(Future<void> gate) async {
    if (_started) return;
    _started = true;
    _state = CatalogLoadState.loading;
    notifyListeners();
    await gate;
    if (_disposed) return;
    await load();
  }

  Future<void> load() {
    _started = true;
    final generation = ++_generation;
    _state = CatalogLoadState.loading;
    notifyListeners();
    late final Future<void> request;
    request = _load(generation).whenComplete(() {
      if (identical(_inflight, request)) _inflight = null;
    });
    _inflight = request;
    return request;
  }

  Future<void> _load(int generation) async {
    try {
      final items = await _repository.list(kind: _kind);
      if (_disposed || generation != _generation) return;
      _items = items;
      _error = null;
      _state = CatalogLoadState.ready;
    } on Object catch (error) {
      if (_disposed || generation != _generation) return;
      _error = error.toString();
      _state = CatalogLoadState.error;
    }
    if (!_disposed) {
      notifyListeners();
      if (_store?.isKindInvalidated(_kind) ?? false) unawaited(load());
    }
  }

  void _handleStoreChanged() {
    if (_disposed) return;
    final store = _store!;
    var changed = false;
    final items = <CatalogItem>[];
    for (final item in _items) {
      final latest = store.findListItemById(item.id) ?? item;
      if (!identical(item, latest)) changed = true;
      items.add(latest);
    }
    if (changed) _items = items;
    if (store.isKindInvalidated(_kind) &&
        _started &&
        _state != CatalogLoadState.loading) {
      unawaited(load());
      return;
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _inflight = null;
    _store?.removeListener(_handleStoreChanged);
    super.dispose();
  }
}

CatalogStore? _catalogStore(CatalogRepository repository) =>
    repository is CatalogStore ? repository : null;
