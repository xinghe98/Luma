// 图片库全屏预览的翻页会话控制器：记录预览打开那一刻的条目顺序，
// 并在用户滑到已加载边界时通过 [loadMore] 追加同筛选条件的后续页。
// 会话内的顺序不再跟随来源列表刷新，因此预览期间列表重排不会移动当前图片；
// 新出现的 id 追加到尾部，不插入到已经看过的图片之前。
// 预览内删除通过 [removeById] 移除当前图；[isRemoved] 过滤迟到分页里
// 已在别处删除的条目，保证被删图片不会借新页回到会话。
// 生命周期由创建方（目前是图片库页）持有并 dispose，预览对话框只订阅不销毁。
import 'package:flutter/foundation.dart';

import '../../data/models/media_item.dart';

/// 一页已加载的图片条目；[hasMore] 表示来源还有未拉取的后续页。
class ImageGalleryPage {
  /// 创建一页已加载结果；[items] 为该页在来源排序下的完整快照，
  /// [hasMore] 表示来源是否还有可继续拉取的后续页。
  const ImageGalleryPage({required this.items, required this.hasMore});

  /// 该页在来源排序下的完整条目快照。
  final List<MediaItem> items;

  /// 来源是否还有下一页可加载。
  final bool hasMore;
}

/// 图片预览的上一张/下一张会话状态。
///
/// 构造时以 [items] 的当前顺序为会话基准，[initialId] 指定首张图片。
/// [next] 前进到末尾且 [hasMore] 为真时会先调用 [loadMore] 拉取下一页，
/// 再切换到该页第一张；期间失败保留当前图片并允许重试。
/// 前进操作串行执行，进行中的多余 next 会被忽略；两端不回绕。
/// [removeById] 删除当前图后优先进入下一张，否则退回上一张；
/// 删除最后一张且来源还有后续页时先补拉一页，仍无图则会话变空（[currentItem] 为 null）。
class ImageGalleryController extends ChangeNotifier {
  /// 创建图片预览会话；[items] 必须非空且包含 [initialId] 对应的条目，
  /// 否则在调试模式下断言失败。会话内顺序以构造时快照为准，不再跟随来源重排。
  ImageGalleryController({
    required List<MediaItem> items,
    required String initialId,
    bool hasMore = false,
    Future<ImageGalleryPage> Function()? loadMore,
    bool Function(String id)? isRemoved,
  }) : _hasMore = hasMore,
       _loadMore = loadMore,
       _isRemoved = isRemoved,
       assert(items.isNotEmpty, '图片预览会话至少需要一张图片'),
       assert(
         items.any((item) => item.id == initialId),
         'initialId 必须存在于 items 快照中',
       ) {
    _merge(items);
    final initialIndex = _indexOfId(initialId);
    _index = initialIndex < 0 ? 0 : initialIndex;
  }

  final List<MediaItem> _items = [];
  final Set<String> _ids = {};
  final Set<String> _removedIds = {};
  final Future<ImageGalleryPage> Function()? _loadMore;

  /// 由宿主提供（通常委托 MediaController.isDeleted）；
  /// 返回 true 的 id 在后续分页合并时跳过，防止删除后借旧页回归。
  final bool Function(String id)? _isRemoved;

  int _index = 0;
  bool _hasMore;
  bool _navigating = false;
  bool _loadingMore = false;
  String? _error;
  bool _disposed = false;

  /// 当前显示的图片；会话内全部图片被删除后为 null，预览应关闭。
  MediaItem? get currentItem => _items.isEmpty ? null : _items[_index];

  /// 会话内是否已无可用图片（仅删除路径会出现；构造时至少有一张）。
  bool get isEmpty => _items.isEmpty;

  /// 当前图片在会话顺序中的下标，从 0 开始。
  int get currentIndex => _index;

  /// 会话当前可见的图片总数，包含已追加的后续页。
  int get length => _items.length;

  bool get canPrevious => _index > 0;

  /// 未到末尾，或末尾之后来源仍有可拉取的页。
  bool get canNext => _index < _items.length - 1 || _hasMore;

  /// 是否正在为翻到下一页拉取远程分页。
  bool get isLoadingMore => _loadingMore;

  /// 最近一次拉取或翻页的失败信息；成功后清除。
  String? get error => _error;

  /// 把新一页按 id 去重追加到尾部；会话内已有的条目原位保留，
  /// 因此来源列表重排或抢先加载都不会改变已打开图片的顺序。
  /// [_isRemoved] 判定已删除的条目不再进入会话，防止旧页把被删图片带回。
  void _merge(List<MediaItem> items) {
    for (final item in items) {
      if (_removedIds.contains(item.id) || (_isRemoved?.call(item.id) ?? false)) {
        continue;
      }
      if (_ids.add(item.id)) _items.add(item);
    }
  }

  int _indexOfId(String id) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].id == id) return i;
    }
    return -1;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 会话中是否已存在该 id；供分页来源过滤重复条目。
  bool containsId(String id) => _ids.contains(id);

  /// 是否有翻页/分页请求进行中；删除等破坏性操作应等待其落定。
  bool get isBusy => _navigating;

  /// 前进到下一张；在已加载末尾时先等待 [loadMore] 拉取下一页再进入。
  /// 失败时停留在当前图片，[error] 记录原因，可再次调用重试。
  Future<void> next() async {
    if (_disposed || _navigating) return;
    if (_index < _items.length - 1) {
      _index++;
      _error = null;
      _notify();
      return;
    }
    if (!_hasMore || _loadMore == null) return;
    _navigating = true;
    _loadingMore = true;
    _error = null;
    _notify();
    try {
      final page = await _loadMore();
      if (_disposed) return;
      _merge(page.items);
      _hasMore = page.hasMore;
      if (_index < _items.length - 1) {
        _index++;
      }
    } on Object catch (e) {
      if (_disposed) return;
      _error = e.toString();
    } finally {
      if (!_disposed) {
        _navigating = false;
        _loadingMore = false;
        _notify();
      }
    }
  }

  /// 退回上一张；首张或翻页进行中时不动作，不回绕到末尾。
  void previous() {
    if (_disposed || _navigating || _index <= 0) return;
    _index--;
    _error = null;
    _notify();
  }

  /// 按 id 移除会话中的图片（预览内删除成功后调用，删除确认时锁定的目标）。
  /// 移除当前图后原下一张顶到被删位置直接显示；删除的是末位则退回上一张；
  /// 全部删空且来源还有后续页时先补拉一页再进入其首张，避免停在已删除图片上。
  /// 补页失败保留空会话并记录 [error]；会话清空后 [currentItem] 返回 null。
  /// 返回 false 表示控制器已释放、翻页进行中或 id 不在会话中，本次未移除。
  Future<bool> removeById(String id) async {
    if (_disposed || _navigating) return false;
    final removedIndex = _indexOfId(id);
    if (removedIndex < 0) return false;
    _items.removeAt(removedIndex);
    _ids.remove(id);
    _removedIds.add(id);
    // 删除点在当前项之前时当前索引前移一位，仍指向同一张图；
    // 删除点即当前项时 index 不变，原下一张顶上来成为新当前图；
    // 删除的是末位元素时 index 越界，退回最后一张。
    if (removedIndex < _index) {
      _index--;
    } else if (_index >= _items.length) {
      _index = _items.length - 1;
    }
    if (_index < 0) _index = 0;
    if (_items.isNotEmpty) {
      _error = null;
      _notify();
      return true;
    }
    // 已加载列表清空：来源还有后续页时补拉，防止预览停在空会话。
    if (_hasMore && _loadMore != null) {
      _navigating = true;
      _loadingMore = true;
      _error = null;
      _notify();
      try {
        do {
          final page = await _loadMore();
          if (_disposed) return false;
          _merge(page.items);
          _hasMore = page.hasMore;
        } while (_items.isEmpty && _hasMore);
      } on Object catch (e) {
        if (_disposed) return false;
        _error = e.toString();
      } finally {
        if (!_disposed) {
          _navigating = false;
          _loadingMore = false;
          _notify();
        }
      }
      return true;
    }
    _hasMore = false;
    _error = null;
    _notify();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
