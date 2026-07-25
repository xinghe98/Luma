import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/services/connection_service.dart';

void main() {
  group('MockMediaRepository', () {
    late MockMediaRepository repository;

    setUp(() => repository = MockMediaRepository());

    test('contains the required media samples', () async {
      final items = await repository.loadMedia();
      expect(items.where((item) => item.type == MediaType.video).length, 20);
      expect(items.where((item) => item.type == MediaType.image).length, 12);
      expect(items.any((item) => item.isPortrait), isTrue);
      expect(
        items.any((item) => item.watchStatus == WatchStatus.watching),
        isTrue,
      );
    });

    test('filters can be combined', () async {
      final results = filterMediaItems(
        await repository.loadMedia(),
        const MediaFilter(text: '夜', type: MediaType.video, tag: '夜景'),
      );
      expect(results, isNotEmpty);
      expect(results.every((item) => item.type == MediaType.video), isTrue);
      expect(results.every((item) => item.tags.contains('夜景')), isTrue);
    });

    test('mutations are reflected and progress is clamped', () async {
      final original = (await repository.loadMedia()).first;
      await repository.setFavorite(original.id, !original.isFavorite);
      await repository.saveNote(original.id, '测试笔记');
      await repository.updateProgress(
        original.id,
        original.duration.inMilliseconds,
      );
      final updated = (await repository.loadMedia()).first;
      expect(updated.isFavorite, !original.isFavorite);
      expect(updated.note, '测试笔记');
      expect(updated.progress, 1);
      expect(updated.completed, isTrue);
    });

    test('sort order is deterministic', () async {
      final items = await repository.loadMedia();
      final byTitle = filterMediaItems(
        items,
        const MediaFilter(sort: MediaSort.title),
      );
      final byDuration = filterMediaItems(
        items,
        const MediaFilter(sort: MediaSort.duration),
      );
      expect(
        byTitle.first.title.compareTo(byTitle.last.title),
        lessThanOrEqualTo(0),
      );
      expect(byDuration.first.duration >= byDuration.last.duration, isTrue);
    });
  });

  test('connection service returns all states', () async {
    final service = MockConnectionService();
    expect(
      await service.login(
        'http://192.168.1.10:8096',
        const LoginCredentials(username: 'test', password: 'test-password'),
      ),
      ConnectionResult.success,
    );
    expect(
      await service.login(
        'http://luma-offline.local:8096',
        const LoginCredentials(username: 'test', password: 'test-password'),
      ),
      ConnectionResult.unreachable,
    );
    expect(
      await service.login(
        'not-an-address',
        const LoginCredentials(username: 'test', password: 'test-password'),
      ),
      ConnectionResult.invalidAddress,
    );
  });
}
