import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/api/api_client.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/api/api_session_interceptor.dart';
import 'package:luma/data/repositories/api_media_repository.dart';
import 'package:luma/data/repositories/api_source_repository.dart';
import 'package:luma/data/repositories/source_repository.dart';
import 'package:luma/data/models/api_source.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/services/api_connection_service.dart';
import 'package:luma/data/services/connection_service.dart';
import 'package:luma/data/storage/credential_store.dart';
import 'package:luma/data/storage/server_alias_store.dart';

void main() {
  test(
    'API repository paginates, authenticates and retries revisions',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var mediaRequests = 0;
      var patchRequests = 0;
      final authorizations = <String?>[];
      final watchStatuses = <String?>[];

      server.listen((request) async {
        authorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        final path = request.uri.path;
        if (path == '/custom/media') {
          mediaRequests++;
          watchStatuses.add(request.uri.queryParameters['watch_status']);
          final cursor = request.uri.queryParameters['cursor'];
          await _json(
            request.response,
            cursor == null
                ? {
                    'items': [_summary],
                    'next_cursor': 'next-page',
                  }
                : {'items': <Object>[], 'next_cursor': null},
          );
          return;
        }
        if (path == '/custom/media/media-1' && request.method == 'GET') {
          await _json(request.response, _detail);
          return;
        }
        if (path == '/custom/media/media-1/user-data' &&
            request.method == 'GET') {
          await _json(request.response, _userData(revision: 2));
          return;
        }
        if (path == '/custom/media/media-1/user-data' &&
            request.method == 'PATCH') {
          patchRequests++;
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          if (patchRequests == 1) {
            expect(body['base_revision'], 1);
            await _json(request.response, {
              'error': {
                'code': 'REVISION_CONFLICT',
                'message': 'stale revision',
                'details': null,
              },
            }, status: HttpStatus.conflict);
          } else {
            expect(body['base_revision'], 2);
            await _json(
              request.response,
              _userData(revision: 3, favorite: true),
            );
          }
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final session = ApiSession(
        origin: 'http://${server.address.host}:${server.port}',
        token: 'secret-token',
      );
      final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
      addTearDown(dio.close);
      final repository = ApiMediaRepository(
        ApiClient(dio, apiPrefix: '/custom/'),
        _TestSourceRepository(),
      );

      final items = await repository.loadMedia();
      final updated = await repository.setFavorite('media-1', true);
      final watched = await repository.search(
        const MediaFilter(watchStatus: WatchStatus.watched),
      );
      final detail = await repository.loadDetail('media-1');

      expect(items, hasLength(1));
      expect(items.single.title, 'Sample');
      expect(items.single.addedAt.isUtc, isTrue);
      expect(watched, hasLength(1));
      expect(mediaRequests, 4);
      expect(watchStatuses, contains('completed'));
      expect(patchRequests, 2);
      expect(updated.isFavorite, isTrue);
      expect(updated.userDataRevision, 3);
      expect(detail.sourceName, 'Main Library');
      expect(authorizations, everyElement('Bearer secret-token'));
    },
  );

  test('updateProgress sends absolute position_ms', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    int? receivedPosition;

    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/custom/media') {
        await _json(request.response, {
          'items': [
            {..._summary, 'duration_ms': null, 'progress_ms': 0},
          ],
          'next_cursor': null,
        });
        return;
      }
      if (path == '/custom/media/media-1/progress' && request.method == 'PUT') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        receivedPosition = body['position_ms'] as int?;
        await _json(
          request.response,
          _userData(revision: 2, progressMs: body['position_ms'] as int),
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final session = ApiSession(
      origin: 'http://${server.address.host}:${server.port}',
      token: 'secret-token',
    );
    final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
    addTearDown(dio.close);
    final repository = ApiMediaRepository(
      ApiClient(dio, apiPrefix: '/custom/'),
      _TestSourceRepository(),
    );

    await repository.loadMedia();
    final updated = await repository.updateProgress('media-1', 12345);
    expect(receivedPosition, 12345);
    expect(updated.userDataRevision, 2);
  });

  test('refresh keeps cache available until replacement succeeds', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var mediaHits = 0;

    server.listen((request) async {
      if (request.uri.path == '/custom/media') {
        mediaHits++;
        if (mediaHits == 1) {
          await _json(request.response, {
            'items': [_summary],
            'next_cursor': null,
          });
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await _json(request.response, {
          'items': [
            {..._summary, 'title': 'Refreshed'},
          ],
          'next_cursor': null,
        });
        return;
      }
      if (request.uri.path == '/custom/media/media-1/progress') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        await _json(
          request.response,
          _userData(revision: 2, progressMs: body['position_ms'] as int),
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final session = ApiSession(
      origin: 'http://${server.address.host}:${server.port}',
      token: 'token',
    );
    final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
    addTearDown(dio.close);
    final repository = ApiMediaRepository(
      ApiClient(dio, apiPrefix: '/custom/'),
      _TestSourceRepository(),
    );

    await repository.loadMedia();
    final refresh = repository.refresh();
    final updated = await repository.updateProgress('media-1', 5000);
    expect(updated.progress, greaterThan(0));
    final items = await refresh;
    expect(items.single.title, 'Refreshed');
  });

  test('normalizeOrigin keeps non-root path prefixes', () {
    expect(
      ApiConnectionService.normalizeOrigin(Uri.parse('http://host/luma/')),
      'http://host/luma',
    );
    expect(
      ApiConnectionService.normalizeOrigin(Uri.parse('http://host:8080')),
      'http://host:8080',
    );
  });

  test(
    'source repository loads configured media roots for the picker',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.uri.path, '/custom/admin/media-roots');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer root-token',
        );
        await _json(request.response, {
          'items': ['/media/family', '/media/movies'],
        });
      });
      final session = ApiSession(
        origin: 'http://${server.address.host}:${server.port}',
        token: 'root-token',
      );
      final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
      addTearDown(dio.close);
      final repository = ApiSourceRepository(
        ApiClient(dio, apiPrefix: '/custom/'),
      );

      expect(await repository.listAvailableRoots(), [
        '/media/family',
        '/media/movies',
      ]);
    },
  );

  test('media count uses one authenticated aggregate request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      expect(request.uri.path, '/custom/media/count');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer count-token',
      );
      await _json(request.response, {'count': 321});
    });
    final session = ApiSession(
      origin: 'http://${server.address.host}:${server.port}',
      token: 'count-token',
    );
    final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
    addTearDown(dio.close);
    final repository = ApiMediaRepository(
      ApiClient(dio, apiPrefix: '/custom/'),
      _TestSourceRepository(),
    );

    expect(await repository.countMedia(), 321);
    expect(requests, 1);
  });

  test('failed connection probe leaves the active session untouched', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer candidate-token',
      );
      await _json(request.response, {
        'error': {'code': 'UNAVAILABLE', 'message': 'offline'},
      }, status: HttpStatus.serviceUnavailable);
    });
    final active = ApiSession(
      origin: 'http://active.example.test',
      token: 'active-token',
    );
    final dio = Dio()..interceptors.add(ApiSessionInterceptor(active));
    addTearDown(dio.close);
    final credentials = _MemoryCredentialStore();
    final service = ApiConnectionService(
      client: ApiClient(dio, apiPrefix: '/custom/'),
      apiSession: active,
      credentialStore: credentials,
      aliasStore: const _MemoryAliasStore(),
    );

    final result = await service.test(
      'http://${server.address.host}:${server.port}',
      'candidate-token',
    );

    expect(result, ConnectionResult.unreachable);
    expect(active.origin, 'http://active.example.test');
    expect(active.token, 'active-token');
    expect(credentials.writes, isEmpty);
  });
}

final class _TestSourceRepository implements SourceRepository {
  static final source = Source(
    id: 'source-1',
    name: 'Main Library',
    type: 'local',
    libraryKind: 'personal',
    enabled: true,
    status: 'online',
    lastScanId: null,
    lastSeenAt: null,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<Source?> find(String id) async => id == source.id ? source : null;

  @override
  Future<List<Source>> list({bool refresh = false}) async => [source];
}

final class _MemoryCredentialStore implements CredentialStore {
  final writes = <StoredCredentials>[];

  @override
  Future<void> clear() async {}

  @override
  Future<StoredCredentials?> read() async => null;

  @override
  Future<void> write(StoredCredentials credentials) async {
    writes.add(credentials);
  }
}

final class _MemoryAliasStore implements ServerAliasStore {
  const _MemoryAliasStore();

  @override
  Future<void> clear(String origin) async {}

  @override
  Future<String?> read(String origin) async => null;

  @override
  Future<void> write(String origin, String alias) async {}
}

Future<void> _json(
  HttpResponse response,
  Object body, {
  int status = HttpStatus.ok,
}) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

final _summary = {
  'id': 'media-1',
  'title': 'Sample',
  'filename': 'sample.mp4',
  'media_type': 'video',
  'duration_ms': 100000,
  'width': 1920,
  'height': 1080,
  'thumbnail_url': '/api/v1/media/media-1/thumbnail',
  'card_thumbnail_url': '/api/v1/media/media-1/thumbnail?variant=card',
  'stream_url': '/api/v1/media/media-1/stream',
  'original_url': null,
  'favorite': false,
  'progress_ms': 1000,
  'completed': false,
  'last_played_at': null,
  'user_data_revision': 1,
  'status': 'ready',
  'created_at': '2024-06-01T12:00:00.000Z',
};

final _detail = {
  ..._summary,
  'source_id': 'source-1',
  'mime_type': 'video/mp4',
  'file_size': 1048576,
  'video_codec': 'h264',
  'audio_codec': 'aac',
  'container': 'mov,mp4',
  'bitrate': 1000000,
  'frame_rate_num': 30,
  'frame_rate_den': 1,
  'audio_track_count': 1,
  'orientation': null,
  'captured_at': null,
  'indexed_at': '2024-06-01T12:01:00.000Z',
};

Map<String, Object?> _userData({
  required int revision,
  bool favorite = false,
  int progressMs = 1000,
}) => {
  'media_id': 'media-1',
  'custom_title': null,
  'favorite': favorite,
  'notes': null,
  'progress_ms': progressMs,
  'completed': false,
  'last_played_at': null,
  'tags': <Object>[],
  'revision': revision,
  'created_at': null,
  'updated_at': null,
};
