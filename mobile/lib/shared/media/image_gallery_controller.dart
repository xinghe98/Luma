// 图片库全屏预览的翻页会话控制器：记录预览打开那一刻的条目顺序，
// 并在用户滑到已加载边界时通过 [loadMore] 追加同筛选条件的后续页。
// 会话内的顺序不再跟随来源列表刷新，因此预览期间列表重排不会移动当前图片；
// 新出现的 id 追加到尾部，不插入到已经看过的图片之前。
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
class ImageGalleryController extends ChangeNotifier {
  /// 创建图片预览会话；[items] 必须非空且包含 [initialId] 对应的条目，
  /// 否则在调试模式下断言失败。会话内顺序以构造时快照为准，不再跟随来源重排。
  ImageGalleryController({
    required List<MediaItem> items,
    required String initialId,
    bool hasMore = false,
    Future<ImageGalleryPage> Function()? loadMore,
  }) : _hasMore = hasMore,
       _loadMore = loadMore,
       assert(items.isNotEmpty, '图片预览会话至少需要一张图片'),
       assert(
         items.any((item) => item.id == initialId),
         'initialId 必须存在于 items 快照中',
       ) {
    _merge(items);
    _index = _indexOfId(initialId);
  }

  final List<MediaItem> _items = [];
  final Set<String> _ids = {};
  final Future<ImageGalleryPage> Function()? _loadMore;

  int _index = 0;
  bool _hasMore;
  bool _navigating = false;
  bool _loadingMore = false;
  String? _error;
  bool _disposed = false;

  /// 当前显示的图片；列表为空时不应出现（首条总会选中一项）。
  MediaItem get currentItem => _items[_index];

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
  void _merge(List<MediaItem> items) {
    for (final item in items) {
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
