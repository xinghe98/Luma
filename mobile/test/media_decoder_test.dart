import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/decoders/media_decoder.dart';

void main() {
  const decoder = MediaDecoder();

  test('new response decodes card thumbnail URL', () {
    final item = decoder.decodeSummary({
      ..._summary,
      'card_thumbnail_url': '/api/v1/media/1/thumbnail?variant=card',
    });
    expect(item.cardThumbnailUrl, endsWith('variant=card'));
  });

  test('old response without card thumbnail remains compatible', () {
    final item = decoder.decodeSummary(_summary);
    expect(item.cardThumbnailUrl, isEmpty);
    expect(item.thumbnailUrl, isNotEmpty);
  });

  test('matched media decodes its catalog route ID', () {
    final item = decoder.decodeSummary({
      ..._summary,
      'catalog_item_id': 'catalog-1',
    });

    expect(item.catalogItemId, 'catalog-1');
  });
}

final _summary = <String, Object?>{
  'id': '1',
  'title': 'Sample',
  'filename': 'sample.jpg',
  'media_type': 'image',
  'duration_ms': null,
  'width': 1200,
  'height': 1800,
  'thumbnail_url': '/api/v1/media/1/thumbnail',
  'stream_url': null,
  'original_url': '/api/v1/media/1/original',
  'favorite': false,
  'progress_ms': 0,
  'completed': false,
  'last_played_at': null,
  'user_data_revision': 0,
  'status': 'ready',
  'created_at': '2026-01-01T00:00:00Z',
};
