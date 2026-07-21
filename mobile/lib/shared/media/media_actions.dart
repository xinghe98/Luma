import '../../data/models/media_item.dart';

/// 打开媒体详情的统一回调。[heroTag] 由卡片所在分区生成，
/// 用于卡片封面与详情页封面之间的 Hero 过渡。
typedef MediaOpenCallback = void Function(MediaItem item, {String? heroTag});
