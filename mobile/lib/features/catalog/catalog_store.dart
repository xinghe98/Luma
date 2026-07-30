// 会话级作品仓库汇合列表、详情、收藏与失效状态。
// 它包装 CatalogRepository，并在断开连接或应用销毁时停止发布变更。
import 'package:flutter/foundation.dart';

import '../../data/models/api_catalog.dart';
import '../../data/repositories/catalog_repository.dart';

/// 在当前连接会话内共享最新作品快照，并把写操作转发给底层仓库。
final class CatalogStore extends ChangeNotifier implements CatalogRepository {
  /// 包装底层仓库，并把本会话读取与写入汇合为共享快照。
  CatalogStore(this._repository);

  final CatalogRepository _repository;
  final Map<String, CatalogItem> _items = {};
  final Map<String, CatalogItem> _details = {};
  final Map<String, CatalogFavorite> _favorites = {};
  final Map<CatalogKind, int> _kindInvalidations = {};
  final Map<CatalogKind, int> _kindFreshness = {};
  final Map<String, int> _itemInvalidations = {};
  final Map<String, int> _itemFreshness = {};
  int _generation = 0;
  bool _disposed = false;

  /// 返回会话中已知的最新作品；尚未加载时返回 null。
  CatalogItem? findById(String id) => _details[id] ?? _items[id];

  /// 返回列表应展示的最新条目，列表刷新结果优先于详情快照。
  CatalogItem? findListItemById(String id) => _items[id] ?? _details[id];

  /// 返回不早于条目自身版本的作品收藏状态。
  CatalogFavorite favoriteFor(CatalogItem item) {
    final saved = _favorites[item.id];
    if (saved != null && saved.revision >= item.favoriteRevision) return saved;
    return CatalogFavorite(
      favorite: item.favorite,
      revision: item.favoriteRevision,
    );
  }

  /// 缓存来源页已有条目；可关闭通知以避免路由发起前重建来源页。
  void rememberAll(Iterable<CatalogItem> items, {bool notify = true}) {
    var changed = false;
    for (final item in items) {
      if (!identical(_items[item.id], item)) {
        _items[item.id] = item;
        changed = true;
      }
      _rememberFavorite(item);
    }
    if (changed && notify && !_disposed) notifyListeners();
  }

  /// 标记播放关联作品过期；已知类型只刷新对应 shelf，未知时刷新两类。
  void invalidate(String? catalogId) {
    if (_disposed || catalogId == null || catalogId.isEmpty) return;
    _itemInvalidations[catalogId] = (_itemInvalidations[catalogId] ?? 0) + 1;
    final kind = _items[catalogId]?.kind;
    if (kind == null) {
      for (final value in CatalogKind.values) {
        _kindInvalidations[value] = (_kindInvalidations[value] ?? 0) + 1;
      }
    } else {
      _kindInvalidations[kind] = (_kindInvalidations[kind] ?? 0) + 1;
    }
    notifyListeners();
  }

  /// 指示某一作品列表是否需要重新向服务端确认播放状态。
  bool isKindInvalidated(CatalogKind kind) =>
      (_kindInvalidations[kind] ?? 0) > (_kindFreshness[kind] ?? 0);

  /// 指示某一详情是否需要重新读取。
  bool isItemInvalidated(String id) =>
      (_itemInvalidations[id] ?? 0) > (_itemFreshness[id] ?? 0);

  /// 清除当前服务器的全部会话快照，并通知仍在树中的订阅者。
  void clear() {
    if (_disposed) return;
    _generation++;
    _items.clear();
    _details.clear();
    _favorites.clear();
    _kindInvalidations.clear();
    _kindFreshness.clear();
    _itemInvalidations.clear();
    _itemFreshness.clear();
    notifyListeners();
  }

  @override
  Future<List<CatalogItem>> list({CatalogKind? kind, String? query}) async {
    final generation = _generation;
    final requestedRevision = kind == null ? 0 : _kindInvalidations[kind] ?? 0;
    final items = await _repository.list(kind: kind, query: query);
    if (_disposed || generation != _generation) return const [];
    rememberAll(items, notify: false);
    if (kind != null) _kindFreshness[kind] = requestedRevision;
    notifyListeners();
    return items;
  }

  @override
  Future<CatalogItem> detail(String id) async {
    final generation = _generation;
    final requestedRevision = _itemInvalidations[id] ?? 0;
    final item = await _repository.detail(id);
    if (_disposed || generation != _generation) {
      throw StateError('Catalog session changed');
    }
    _details[id] = item;
    rememberAll([item], notify: false);
    _itemFreshness[id] = requestedRevision;
    notifyListeners();
    return item;
  }

  @override
  Future<CatalogFavorite> setFavorite({
    required String catalogId,
    required bool favorite,
    required int revision,
  }) async {
    final generation = _generation;
    final saved = await _repository.setFavorite(
      catalogId: catalogId,
      favorite: favorite,
      revision: revision,
    );
    if (!_disposed && generation == _generation) {
      _favorites[catalogId] = saved;
      notifyListeners();
    }
    return saved;
  }

  void _rememberFavorite(CatalogItem item) {
    final saved = _favorites[item.id];
    if (saved == null || item.favoriteRevision >= saved.revision) {
      _favorites[item.id] = CatalogFavorite(
        favorite: item.favorite,
        revision: item.favoriteRevision,
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
