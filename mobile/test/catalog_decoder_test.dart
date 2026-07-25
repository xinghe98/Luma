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

  test('catalog decoder accepts optional scraping metadata', () {
    const decoder = CatalogDecoder();
    final item = decoder.decode({
      'id': 'catalog-1',
      'source_id': 'source-1',
      'kind': 'movie',
      'title': '三体',
      'original_title': 'The Three-Body Problem',
      'overview': '一段跨越时空的故事。',
      'tagline': '',
      'release_date': '2023-01-15',
      'end_date': '',
      'certification': 'PG-13',
      'community_rating': 8.4,
      'vote_count': 123,
      'genres': [
        {'id': '18', 'name': '剧情'},
      ],
      'countries': [],
      'studios': [],
      'credits': [
        {
          'person_id': 'person-1',
          'name': '演员',
          'role': 'actor',
          'character': '角色',
          'order': 0,
        },
      ],
      'external_ids': {'tmdb': '123'},
      'metadata_status': 'ready',
      'metadata_revision': 2,
      'metadata_error_code': '',
      'provider': 'tmdb',
      'provider_item_id': '123',
      'identity_locked': false,
      'year': 2023,
      'media_count': 1,
      'episode_count': 0,
      'completed_count': 0,
      'playable_media_id': 'media-1',
      'thumbnail_url': '/api/v1/media/media-1/thumbnail',
      'poster_url': '/api/v1/catalog/artwork/poster-1',
      'backdrop_url': '/api/v1/catalog/artwork/backdrop-1',
      'duration_ms': 3600000,
      'resolution': '1920×1080',
      'progress_ms': 0,
      'completed': false,
      'updated_at': '2026-07-25T08:00:00Z',
    });

    expect(item.originalTitle, 'The Three-Body Problem');
    expect(item.communityRating, 8.4);
    expect(item.genres.single.name, '剧情');
    expect(item.credits.single.character, '角色');
    expect(item.externalIds['tmdb'], '123');
    expect(item.backdropUrl, '/api/v1/catalog/artwork/backdrop-1');
  });
}
