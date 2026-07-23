import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';

void main() {
  test('image library includes images from every video source type', () {
    final images = filterMediaItems([
      _media('personal-image', MediaType.image, 'personal'),
      _media('movie-image', MediaType.image, 'movies'),
      _media('tv-image', MediaType.image, 'tv'),
      _media('movie-video', MediaType.video, 'movies'),
    ], const MediaFilter(type: MediaType.image));

    expect(images.map((item) => item.id), [
      'personal-image',
      'movie-image',
      'tv-image',
    ]);
  });
}

MediaItem _media(String id, MediaType type, String libraryKind) => MediaItem(
  id: id,
  title: id,
  type: type,
  duration: Duration.zero,
  resolution: '',
  format: '',
  fileSize: '',
  directory: '',
  tags: const [],
  addedAt: DateTime.utc(2026),
  artSeed: 1,
  libraryKind: libraryKind,
);
