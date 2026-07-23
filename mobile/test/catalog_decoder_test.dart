import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/decoders/catalog_decoder.dart';
import 'package:luma/data/models/api_catalog.dart';

void main() {
  test('catalog decoder preserves work and episode playback fields', () {
    const decoder = CatalogDecoder();
    final item = decoder.decode({
      'id': 'catalog-1',
      'source_id': 'source-1',
      'kind': 'series',
      'title': '漫长的季节',
      'year': 2023,
      'media_count': 2,
      'episode_count': 2,
      'completed_count': 1,
      'playable_media_id': 'episode-2',
      'thumbnail_url': '/api/v1/media/episode-1/thumbnail',
      'duration_ms': 3600000,
      'resolution': '1920×1080',
      'progress_ms': 120000,
      'completed': false,
      'updated_at': '2026-07-21T08:00:00Z',
      'episodes': [
        {
          'id': 'episode-view-1',
          'season_number': 1,
          'episode_number': 1,
          'title': '第 1 集',
          'media_id': 'episode-1',
          'duration_ms': 3600000,
          'resolution': '3840×2160',
          'progress_ms': 3600000,
          'completed': true,
          'thumbnail_url': '/api/v1/media/episode-1/thumbnail',
        },
      ],
    });

    expect(item.kind, CatalogKind.series);
    expect(item.episodes.single.completed, isTrue);
    expect(item.playableMediaId, 'episode-2');
    expect(item.resolution, '1920×1080');
    expect(item.episodes.single.resolution, '3840×2160');
  });

  test('catalog issue decoder uses public snake case contract', () {
    const decoder = CatalogDecoder();
    final issue = decoder.decodeIssue({
      'media_id': 'media-1',
      'filename': 'clip.mkv',
      'source_id': 'source-1',
      'library_kind': 'tv',
      'suggested_title': '剧名',
      'season_number': null,
      'episode_number': null,
    });
    expect(issue.mediaId, 'media-1');
    expect(issue.libraryKind, 'tv');
  });
}
