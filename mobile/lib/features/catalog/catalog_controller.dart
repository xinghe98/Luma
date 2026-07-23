import 'package:flutter/foundation.dart';

import '../../data/models/api_catalog.dart';
import '../../data/repositories/catalog_repository.dart';

enum CatalogLoadState { idle, loading, ready, error }

final class CatalogController extends ChangeNotifier {
  CatalogController(this._repository, {required CatalogKind kind})
    : _kind = kind;

  final CatalogRepository _repository;
  final CatalogKind _kind;
  CatalogLoadState _state = CatalogLoadState.idle;
  List<CatalogItem> _items = const [];
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

  /// Starts the first request once. Collection routes call this immediately;
  /// overview sections wait until they become relevant on screen.
  Future<void> ensureLoaded() {
    if (_started) return _inflight ?? Future.value();
    return load();
  }

  /// Explicit refresh or retry. Unlike [ensureLoaded], this always starts a
  /// new generation and invalidates an older response.
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
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _inflight = null;
    super.dispose();
  }
}
