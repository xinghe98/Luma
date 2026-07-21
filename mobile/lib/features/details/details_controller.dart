import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/models/media_item.dart';

class DetailsController extends ChangeNotifier {
  DetailsController({required this.mediaId, required this.media}) {
    media.addListener(notifyListeners);
    unawaited(media.loadDetail(mediaId));
  }

  final String mediaId;
  final MediaController media;

  MediaItem? get item => media.findById(mediaId);
  String? get detailError => media.detailError;
  bool get isLoading => media.detailLoading && item == null;
  bool get isMissing => item == null && !media.detailLoading;

  Future<void> reload() => media.loadDetail(mediaId);
  Future<void> toggleFavorite() => media.toggleFavorite(mediaId);
  Future<void> saveNote(String note) => media.saveNote(mediaId, note);

  @override
  void dispose() {
    media.removeListener(notifyListeners);
    super.dispose();
  }
}
