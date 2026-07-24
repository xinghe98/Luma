import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/controllers/media_controller.dart';
import '../../data/models/media_item.dart';

class DetailsController extends ChangeNotifier {
  /// Defers the initial detail request so a Hero or route transition can finish
  /// before decoding a larger artwork variant and notifying both pages.
  DetailsController({
    required this.mediaId,
    required this.media,
    this.initialLoadDelay = Duration.zero,
  }) {
    media.addListener(notifyListeners);
    unawaited(_loadInitialDetail());
  }

  final String mediaId;
  final MediaController media;
  final Duration initialLoadDelay;
  bool _disposed = false;

  /// Starts the first request after the configured transition-safe delay.
  Future<void> _loadInitialDetail() async {
    if (initialLoadDelay > Duration.zero) {
      await Future<void>.delayed(initialLoadDelay);
    }
    if (!_disposed) await media.loadDetail(mediaId);
  }

  MediaItem? get item => media.findById(mediaId);
  String? get detailError => media.detailError;
  bool get isLoading => media.detailLoading && item == null;
  bool get isMissing => item == null && !media.detailLoading;

  Future<void> reload() => media.loadDetail(mediaId);
  Future<void> toggleFavorite() => media.toggleFavorite(mediaId);
  Future<void> saveNote(String note) => media.saveNote(mediaId, note);

  @override
  void dispose() {
    _disposed = true;
    media.removeListener(notifyListeners);
    super.dispose();
  }
}
