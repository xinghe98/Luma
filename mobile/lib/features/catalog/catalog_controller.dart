import 'package:flutter/foundation.dart';

import '../../data/models/api_catalog.dart';
import '../../data/repositories/catalog_repository.dart';

enum CatalogLoadState { loading, ready, error }

final class CatalogController extends ChangeNotifier {
  CatalogController(this._repository, {required CatalogKind kind})
    : _kind = kind {
    load();
  }

  final CatalogRepository _repository;
  final CatalogKind _kind;
  CatalogLoadState _state = CatalogLoadState.loading;
  List<CatalogItem> _items = const [];
  String? _error;
  int _generation = 0;
  bool _disposed = false;

  CatalogKind get kind => _kind;
  CatalogLoadState get state => _state;
  List<CatalogItem> get items => _items;
  String? get error => _error;

  Future<void> load() async {
    final generation = ++_generation;
    _state = CatalogLoadState.loading;
    notifyListeners();
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
    super.dispose();
  }
}
