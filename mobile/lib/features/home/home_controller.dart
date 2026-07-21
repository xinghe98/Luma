import 'package:flutter/foundation.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/models/media_item.dart';

class HomeController extends ChangeNotifier {
  HomeController(this.media) {
    media.addListener(notifyListeners);
  }

  final MediaController media;

  List<MediaItem> get continuing =>
      media.continueWatching.take(8).toList(growable: false);

  /// 首页媒体列表默认已按 created_at desc 拉取，直接取前几项避免全库 sort。
  List<MediaItem> get recent => media.items.take(8).toList(growable: false);

  List<MediaItem> get favorites {
    final result = <MediaItem>[];
    for (final item in media.items) {
      if (!item.isFavorite) continue;
      result.add(item);
      if (result.length >= 10) break;
    }
    return result;
  }

  @override
  void dispose() {
    media.removeListener(notifyListeners);
    super.dispose();
  }
}
