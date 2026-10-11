// 验证图片删除在媒体、图库和搜索间同步，并隔离迟到响应及连接切换。
// 测试仓库只持有内存图片；文件权限和索引事务由后端回归覆盖。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/library/library_controller.dart';
import 'package:luma/features/search/search_controller.dart' as feature;

void main() {
  test('删除同步首页、分页图库与搜索，旧摘要不能恢复图片', () async {
    final repository = _DeletionRepository();
    final media = MediaController(repository);
    final library = LibraryController(media: media, fixedType: MediaType.image);
    final search = feature.SearchController(media);
    addTearDown(() { search.dispose(); library.dispose(); media.dispose(); });
    await media.load();
    await library.ensureLoaded();
    search.setType(MediaType.image);
    await Future<void>.delayed(Duration.zero);
    final deleted = repository.items.first;
    final remaining = repository.items.skip(1).map((item) => item.id).toList();

    await media.deleteImage(deleted.id);
    media.remember(deleted);
    media.rememberAll([deleted]);

    expect(media.findById(deleted.id), isNull);
    expect(media.items.map((item) => item.id), remaining);
    expect(library.visibleItems().map((item) => item.id), remaining);
    expect(library.itemCount, remaining.length);
    expect(search.results.map((item) => item.id), remaining);
    expect(media.catalogCount, remaining.length);
  });

  test('删除前发起的刷新、详情和分页回包不能恢复图片', () async {
    final repository = _DeletionRepository();
    final media = MediaController(repository);
    final library = LibraryController(media: media);
    addTearDown(() { library.dispose(); media.dispose(); });
    await media.load();
    await library.ensureLoaded();
    final snapshot = List<MediaItem>.of(repository.items);
    final deleted = snapshot.first;
    repository.refreshGate = Completer<List<MediaItem>>();
    repository.pageGate = Completer<MediaListPage>();
    repository.detailGate = Completer<MediaItem>();
    final refresh = media.refresh();
    final page = library.refresh();
    final detail = media.loadDetail(deleted.id);
    await media.deleteImage(deleted.id);
    repository.refreshGate!.complete(snapshot);
    repository.pageGate!.complete(MediaListPage(items: snapshot, nextCursor: 'next'));
    repository.detailGate!.complete(deleted);
    await Future.wait([refresh, page, detail]);

    expect(media.findById(deleted.id), isNull);
    expect(media.items.map((item) => item.id), isNot(contains(deleted.id)));
    expect(library.visibleItems().map((item) => item.id), isNot(contains(deleted.id)));
    expect(library.hasMore, isTrue);
  });

  test('删除失败保留原图，可在恢复后重试', () async {
    final repository = _DeletionRepository()..failDelete = true;
    final media = MediaController(repository);
    addTearDown(media.dispose);
    await media.load();
    final item = repository.items.first;
    await expectLater(media.deleteImage(item.id), throwsStateError);
    expect(media.findById(item.id), item);
    expect(media.isDeleted(item.id), isFalse);
    repository.failDelete = false;
    await media.deleteImage(item.id);
    expect(media.findById(item.id), isNull);
    expect(repository.items.map((item) => item.id), isNot(contains(item.id)));
  });

  test('换服后忽略旧删除回包并停止排队删除', () async {
    final repository = _DeletionRepository();
    final media = MediaController(repository);
    addTearDown(media.dispose);
    await media.load();
    final first = repository.items[0];
    final second = repository.items[1];
    repository.deleteGate = Completer<void>();
    final firstDelete = media.deleteImage(first.id);
    await Future<void>.delayed(Duration.zero);
    final queuedDelete = media.deleteImage(first.id);
    final firstCheck = expectLater(firstDelete, throwsStateError);
    final queuedCheck = expectLater(queuedDelete, throwsStateError);
    final generation = media.sessionGeneration;
    media.clear();
    media.remember(first);
    media.remember(second);
    repository.deleteGate!.complete();
    await Future.wait([firstCheck, queuedCheck]);
    expect(media.sessionGeneration, greaterThan(generation));
    expect(media.findById(first.id), first);
    expect(media.findById(second.id), second);
    expect(media.isDeleted(first.id), isFalse);
    expect(repository.deleteCalls, [first.id]);
  });

  test('同图删除合并到串行队列，不重复请求或扣减总数', () async {
    final repository = _DeletionRepository();
    final media = MediaController(repository);
    addTearDown(media.dispose);
    await media.load();
    final id = repository.items.first.id;
    final count = repository.items.length;
    await Future.wait([media.deleteImage(id), media.deleteImage(id)]);
    expect(repository.deleteCalls, [id]);
    expect(media.catalogCount, count - 1);
  });
}

class _DeletionRepository extends MockMediaRepository {
  List<MediaItem> items = buildMediaFixtures()
      .where((item) => item.type == MediaType.image).take(3).toList();
  final deleteCalls = <String>[];
  bool failDelete = false;
  Completer<void>? deleteGate;
  Completer<List<MediaItem>>? refreshGate;
  Completer<MediaListPage>? pageGate;
  Completer<MediaItem>? detailGate;

  @override
  Future<List<MediaItem>> loadMedia() async => List.of(items);
  @override
  Future<List<MediaItem>> refresh() => refreshGate?.future ?? loadMedia();
  @override
  Future<List<MediaItem>> loadContinueWatching() async => [];
  @override
  Future<int> countMedia({MediaType? type}) async => items.length;
  @override
  Future<MediaItem> loadDetail(String id) => detailGate?.future ??
      Future.value(items.firstWhere((item) => item.id == id));
  @override
  Future<MediaListPage> searchPage(MediaFilter filter, {String? cursor, int? limit}) async {
    final pending = pageGate;
    if (pending != null) return pending.future;
    return MediaListPage(items: List.of(items), nextCursor: null);
  }

  /// 可暂停或拒绝删除，模拟请求失败和旧连接回包。
  @override
  Future<void> deleteImage(String id) async {
    deleteCalls.add(id);
    if (failDelete) throw StateError('来源不可写');
    await deleteGate?.future;
    items = items.where((item) => item.id != id).toList();
  }
}
