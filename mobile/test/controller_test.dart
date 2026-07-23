import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/app/controllers/session_controller.dart';
import 'package:luma/app/controllers/settings_controller.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/models/api_scan.dart';
import 'package:luma/data/models/api_tag.dart';
import 'package:luma/data/repositories/scan_repository.dart';
import 'package:luma/data/storage/credential_store.dart';
import 'package:luma/data/storage/server_alias_store.dart';
import 'package:luma/data/services/connection_service.dart';
import 'package:luma/features/connection/connection_controller.dart';
import 'package:luma/features/home/widgets/home_header.dart';
import 'package:luma/features/library/library_controller.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/search/search_controller.dart' as feature;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('connection controller connects session and loads media', () async {
    final media = MediaController(MockMediaRepository());
    final session = SessionController();
    final controller = ConnectionController(
      connectionService: _ImmediateConnectionService(),
      sessionController: session,
      mediaController: media,
      successDelay: Duration.zero,
    );
    await controller.connect('http://server.local', 'test-token');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(session.isConnected, isTrue);
    expect(media.items.length, 32);
  });

  test(
    'member connection does not restore administrator-only scan status',
    () async {
      final scans = _CountingScanRepository();
      final dependencies = AppDependencies(
        mediaRepository: MockMediaRepository(),
        connectionService: _MemberConnectionService(),
        settingsController: SettingsController(scanRepository: scans),
      );
      addTearDown(dependencies.dispose);

      expect(
        await dependencies.connection.restore(
          'http://server.local',
          'member-token',
        ),
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(scans.latestAllCalls, 0);
      expect(dependencies.settings.scanError, isNull);
    },
  );

  test(
    'restored connection cancels stale background sync after reset',
    () async {
      final repository = _BlockingMediaRepository();
      final media = MediaController(repository);
      final session = SessionController();
      var syncCalls = 0;
      final controller = ConnectionController(
        connectionService: _ImmediateConnectionService(),
        sessionController: session,
        mediaController: media,
        onConnected: () async {
          syncCalls++;
        },
      );

      expect(
        await controller.restore('http://server.local', 'test-token'),
        isTrue,
      );
      expect(session.isConnected, isTrue);
      await repository.loadStarted.future;
      controller.reset();
      repository.release.complete();
      await Future<void>.delayed(Duration.zero);

      expect(syncCalls, 0);
    },
  );

  test('disconnect invalidates an in-flight saved-session restore', () async {
    final credentials = _PendingCredentialStore();
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: _ImmediateConnectionService(),
      credentialStore: credentials,
    );
    addTearDown(dependencies.dispose);

    final restore = dependencies.restoreSession();
    await credentials.readStarted.future;
    expect(dependencies.restoring.value, isTrue);

    await dependencies.disconnect();
    expect(dependencies.restoring.value, isFalse);

    credentials.complete(
      const StoredCredentials(
        origin: 'http://server.local:8080',
        token: 'test-token',
      ),
    );
    expect(await restore, isFalse);
    expect(dependencies.restoring.value, isFalse);
  });

  test('library controller combines and clears filters', () async {
    final media = MediaController(MockMediaRepository());
    await media.load();
    final controller = LibraryController()
      ..setType(MediaType.video)
      ..applyFilters(const LibraryFilters(favoritesOnly: true));
    expect(
      controller
          .visibleItems(media.items)
          .every((item) => item.type == MediaType.video && item.isFavorite),
      isTrue,
    );
    controller.clearFilters(includeType: true);
    expect(controller.visibleItems(media.items).length, 32);
  });

  test(
    'library controller seeds a bounded first frame from home cache',
    () async {
      final media = MediaController(MockMediaRepository());
      await media.load();
      final controller = LibraryController(
        fixedType: MediaType.video,
        media: media,
      );

      final loading = controller.ensureLoaded();
      final firstFrame = controller.visibleItems();
      expect(firstFrame, isNotEmpty);
      expect(firstFrame.length, lessThanOrEqualTo(12));
      expect(firstFrame.every((item) => item.type == MediaType.video), isTrue);
      await loading;
      controller.dispose();
    },
  );

  test('search controller records terms and clears criteria', () {
    final media = MediaController(MockMediaRepository());
    final controller = feature.SearchController(media)
      ..setQuery('Tokyo')
      ..setType(MediaType.video)
      ..remember('Tokyo');
    expect(controller.recent.first, 'Tokyo');
    expect(controller.hasCriteria, isTrue);
    controller.clearCriteria();
    expect(controller.hasCriteria, isFalse);
  });

  test('home greeting follows the device local hour', () {
    expect(greetingForHour(5), '早上好');
    expect(greetingForHour(11), '早上好');
    expect(greetingForHour(12), '下午好');
    expect(greetingForHour(17), '下午好');
    expect(greetingForHour(18), '晚上好');
    expect(greetingForHour(3), '晚上好');
  });

  test('player controller clamps seeks and updates controls', () async {
    final media = MediaController(MockMediaRepository());
    await media.load();
    final item = media.items.firstWhere((item) => item.type == MediaType.video);
    final controller = PlayerController(item: item, media: media);
    controller.seekBy(-99999);
    expect(controller.position, Duration.zero);
    controller.setSpeed(2);
    controller.setLocked(true);
    expect(controller.speed, 2);
    expect(controller.locked, isTrue);
    controller.dispose();
  });

  test('media controller updates continue watching and notifies', () async {
    final media = MediaController(MockMediaRepository());
    await media.load();
    final item = media.items.firstWhere(
      (entry) =>
          entry.type == MediaType.video &&
          entry.watchStatus == WatchStatus.unwatched,
    );
    var notifications = 0;
    media.addListener(() => notifications++);
    await media.updateProgress(
      item.id,
      (item.duration.inMilliseconds * 0.2).round(),
    );
    expect(media.continueWatching.any((entry) => entry.id == item.id), isTrue);
    expect(notifications, greaterThan(0));
    await media.updateProgress(item.id, item.duration.inMilliseconds);
    expect(media.continueWatching.any((entry) => entry.id == item.id), isFalse);
  });

  test(
    'catalog count is single-flight and stale responses cannot repopulate',
    () async {
      final repository = _BlockingCountMediaRepository();
      final media = MediaController(repository);
      final first = media.refreshCatalogCount();
      final second = media.refreshCatalogCount();
      expect(repository.countCalls, 1);

      media.clear();
      repository.completeCount(99);
      await Future.wait([first, second]);

      expect(media.catalogCount, 0);
      media.dispose();
    },
  );

  test(
    'home media, continue watching and tags begin loading in parallel',
    () async {
      final repository = _ParallelMediaRepository();
      final media = MediaController(repository);
      final loading = media.load();

      await Future.wait([
        repository.mediaStarted.future,
        repository.continueStarted.future,
        repository.tagsStarted.future,
      ]);
      expect(repository.refreshCalls, 0);

      repository.complete();
      await loading;
      expect(media.loadState, LoadState.ready);
      media.dispose();
    },
  );

  test('media controller findById is null-safe', () async {
    final media = MediaController(MockMediaRepository());
    await media.load();
    expect(media.findById('missing'), isNull);
    expect(media.findById(media.items.first.id), isNotNull);
  });

  test(
    'rememberAll caches library pages without polluting home feed',
    () async {
      final media = MediaController(MockMediaRepository());
      await media.load();
      final homeIDs = media.items.map((item) => item.id).toList();
      final external = MediaItem(
        id: 'library-page-only',
        title: '分页条目',
        type: MediaType.image,
        duration: Duration.zero,
        resolution: '640×400',
        format: 'JPG',
        fileSize: '',
        directory: '',
        tags: const [],
        addedAt: DateTime.utc(2026),
        artSeed: 1,
        thumbnailUrl: '/thumbnail',
        cardThumbnailUrl: '/thumbnail?variant=card',
      );

      media.rememberAll([external], notify: false);

      expect(media.items.map((item) => item.id), homeIDs);
      expect(media.findById(external.id), same(external));
    },
  );

  test('settings controller updates theme, scan and cache', () async {
    final controller = SettingsController(
      scanRepository: _ImmediateScanRepository(),
      scanPollInterval: const Duration(milliseconds: 1),
    );
    final completed = Completer<void>();
    controller.setThemeMode(ThemeMode.light);
    controller.startScan(onComplete: completed.complete);
    await completed.future;
    controller.clearCache();
    expect(controller.themeMode, ThemeMode.light);
    expect(controller.isScanning, isFalse);
    expect(controller.cacheSizeMb, 0);
  });

  test('scan progress is weighted by media count across sources', () async {
    final controller = SettingsController(
      scanRepository: _WeightedScanRepository(),
      scanPollInterval: const Duration(milliseconds: 1),
    );
    final progress = <double>[];
    final completed = Completer<void>();
    controller.addListener(() {
      final value = controller.scanProgress;
      if (value != null) progress.add(value);
    });
    controller.startScan(onComplete: completed.complete);
    await completed.future;
    expect(progress, contains(closeTo(51 / 101, 0.0001)));
  });

  test('restore reports scans interrupted by a server restart', () async {
    final controller = SettingsController(
      scanRepository: _InterruptedScanRepository(),
      scanPollInterval: const Duration(milliseconds: 1),
    );
    await controller.restoreScan();
    expect(controller.isScanning, isFalse);
    expect(controller.scanError, contains('服务器重启中断'));
  });

  test('restore keeps polling completed scans while processing runs', () async {
    final controller = SettingsController(
      scanRepository: _ProcessingScanRepository(),
      scanPollInterval: const Duration(milliseconds: 1),
    );
    await controller.restoreScan();
    expect(controller.isScanning, isFalse);
    expect(controller.scanError, contains('2 个媒体处理失败'));
  });

  test('server aliases are local and can return to the hostname', () async {
    final aliases = _MemoryAliasStore();
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: MockConnectionService(),
      aliasStore: aliases,
    );
    addTearDown(dependencies.dispose);
    dependencies.session.connect(
      const ServerProfile(
        name: '127.0.0.1',
        address: 'http://127.0.0.1:8080',
        token: 'token',
        hostName: '127.0.0.1',
      ),
    );

    await dependencies.updateServerAlias('家庭服务器');
    expect(dependencies.session.server!.name, '家庭服务器');
    expect(await aliases.read('http://127.0.0.1:8080'), '家庭服务器');

    await dependencies.updateServerAlias('');
    expect(dependencies.session.server!.name, '127.0.0.1');
    expect(await aliases.read('http://127.0.0.1:8080'), isNull);
  });
}

class _ImmediateScanRepository implements ScanRepository {
  final _job = ScanJob(
    id: 'scan-1',
    sourceId: 'source-1',
    status: 'completed',
    phase: 'complete',
    discoveredCount: 1,
    processedCount: 1,
    failedCount: 0,
    startedAt: null,
    finishedAt: null,
    errorCode: null,
    errorMessage: null,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    processing: const ProcessingSummary(
      status: 'completed',
      total: 1,
      discovered: 1,
      probing: 0,
      thumbnailing: 0,
      ready: 1,
      failed: 0,
    ),
  );

  @override
  Future<ScanJob> get(String id) async => _job;

  @override
  Future<ScanJob?> latest() async => null;

  @override
  Future<List<ScanJob>> latestAll() async => const [];

  @override
  Future<List<ScanJob>> startAll() async => [_job];
}

class _InterruptedScanRepository implements ScanRepository {
  final _job = ScanJob(
    id: 'scan-interrupted',
    sourceId: 'source-1',
    status: 'interrupted',
    phase: 'finished',
    discoveredCount: 4,
    processedCount: 4,
    failedCount: 0,
    startedAt: null,
    finishedAt: DateTime(2026),
    errorCode: 'SCAN_INTERRUPTED',
    errorMessage: '服务退出导致扫描中断',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    processing: const ProcessingSummary(
      status: 'completed',
      total: 4,
      discovered: 0,
      probing: 0,
      thumbnailing: 0,
      ready: 4,
      failed: 0,
    ),
  );

  @override
  Future<ScanJob> get(String id) async => _job;

  @override
  Future<ScanJob?> latest() async => _job;

  @override
  Future<List<ScanJob>> latestAll() async => [_job];

  @override
  Future<List<ScanJob>> startAll() async => [_job];
}

class _ProcessingScanRepository implements ScanRepository {
  ScanJob _job(String processingStatus, int failed) => ScanJob(
    id: 'scan-processing',
    sourceId: 'source-1',
    status: 'completed',
    phase: 'completed',
    discoveredCount: 10,
    processedCount: 10,
    failedCount: 0,
    startedAt: DateTime(2026),
    finishedAt: DateTime(2026),
    errorCode: null,
    errorMessage: null,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    processing: ProcessingSummary(
      status: processingStatus,
      total: 10,
      discovered: 0,
      probing: processingStatus == 'running' ? 2 : 0,
      thumbnailing: 0,
      ready: processingStatus == 'running' ? 8 : 8,
      failed: failed,
    ),
  );

  @override
  Future<ScanJob> get(String id) async => _job('completed_with_errors', 2);

  @override
  Future<ScanJob?> latest() async => _job('running', 0);

  @override
  Future<List<ScanJob>> latestAll() async => [_job('running', 0)];

  @override
  Future<List<ScanJob>> startAll() async => [_job('running', 0)];
}

class _WeightedScanRepository implements ScanRepository {
  ScanJob _job(String id, int total, int ready) => ScanJob(
    id: id,
    sourceId: id,
    status: 'completed',
    phase: 'completed',
    discoveredCount: total,
    processedCount: total,
    failedCount: 0,
    startedAt: DateTime(2026),
    finishedAt: DateTime(2026),
    errorCode: null,
    errorMessage: null,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    processing: ProcessingSummary(
      status: 'completed',
      total: total,
      discovered: 0,
      probing: 0,
      thumbnailing: 0,
      ready: ready,
      failed: 0,
    ),
  );

  @override
  Future<ScanJob> get(String id) async => switch (id) {
    'small' => _job('small', 1, 1),
    _ => _job('large', 100, 50),
  };

  @override
  Future<ScanJob?> latest() async => null;

  @override
  Future<List<ScanJob>> latestAll() async => const [];

  @override
  Future<List<ScanJob>> startAll() async => [
    _job('small', 1, 0),
    _job('large', 100, 0),
  ];
}

class _MemoryAliasStore implements ServerAliasStore {
  final Map<String, String> values = {};

  @override
  Future<void> clear(String origin) async => values.remove(origin);

  @override
  Future<String?> read(String origin) async => values[origin];

  @override
  Future<void> write(String origin, String alias) async {
    values[origin] = alias;
  }
}

class _BlockingMediaRepository extends MockMediaRepository {
  final loadStarted = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<MediaItem>> loadMedia() async {
    loadStarted.complete();
    await release.future;
    return const [];
  }
}

class _BlockingCountMediaRepository extends MockMediaRepository {
  final _count = Completer<int>();
  var countCalls = 0;

  @override
  Future<int> countMedia({MediaType? type}) {
    countCalls++;
    return _count.future;
  }

  void completeCount(int value) => _count.complete(value);
}

class _ParallelMediaRepository extends MockMediaRepository {
  final mediaStarted = Completer<void>();
  final continueStarted = Completer<void>();
  final tagsStarted = Completer<void>();
  final _release = Completer<void>();
  var refreshCalls = 0;

  void complete() => _release.complete();

  @override
  Future<List<MediaItem>> loadMedia() async {
    mediaStarted.complete();
    await _release.future;
    return const [];
  }

  @override
  Future<List<MediaItem>> loadContinueWatching() async {
    continueStarted.complete();
    await _release.future;
    return const [];
  }

  @override
  Future<List<Tag>> loadTags() async {
    tagsStarted.complete();
    await _release.future;
    return const [];
  }

  @override
  Future<List<MediaItem>> refresh() async {
    refreshCalls++;
    return const [];
  }
}

class _PendingCredentialStore implements CredentialStore {
  final readStarted = Completer<void>();
  final _result = Completer<StoredCredentials?>();

  @override
  Future<void> clear() async {}

  void complete(StoredCredentials? value) => _result.complete(value);

  @override
  Future<StoredCredentials?> read() {
    if (!readStarted.isCompleted) readStarted.complete();
    return _result.future;
  }

  @override
  Future<void> write(StoredCredentials credentials) async {}
}

class _ImmediateConnectionService implements ConnectionService {
  @override
  ServerProfile? connectedProfile;

  @override
  Future<ConnectionResult> test(String address, String token) async {
    connectedProfile = ServerProfile(
      name: 'server.local',
      address: address,
      token: token,
      hostName: 'server.local',
    );
    return ConnectionResult.success;
  }

  @override
  Future<void> disconnect() async {}
}

class _MemberConnectionService implements ConnectionService {
  @override
  ServerProfile? connectedProfile;

  @override
  Future<ConnectionResult> test(String address, String token) async {
    connectedProfile = ServerProfile(
      name: 'server.local',
      address: address,
      token: token,
      hostName: 'server.local',
      userRole: 'member',
      capabilities: const ['media.read', 'user_data.write'],
    );
    return ConnectionResult.success;
  }

  @override
  Future<void> disconnect() async {}
}

class _CountingScanRepository implements ScanRepository {
  var latestAllCalls = 0;

  @override
  Future<ScanJob> get(String id) => throw UnimplementedError();

  @override
  Future<ScanJob?> latest() => throw UnimplementedError();

  @override
  Future<List<ScanJob>> latestAll() async {
    latestAllCalls++;
    return const [];
  }

  @override
  Future<List<ScanJob>> startAll() => throw UnimplementedError();
}
