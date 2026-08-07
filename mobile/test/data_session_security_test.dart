// 会话安全测试通过 ApiConnectionService/ApiSession 验证原子连接和 epoch 生命周期。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/api/api_client.dart';
import 'package:luma/data/api/api_exception.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/api/api_session_interceptor.dart';
import 'package:luma/data/repositories/api_source_repository.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/services/api_connection_service.dart';
import 'package:luma/data/services/connection_service.dart';
import 'package:luma/data/services/device_key_store.dart';
import 'package:luma/data/services/device_name_resolver.dart';
import 'package:luma/data/storage/credential_store.dart';
import 'package:luma/data/storage/server_alias_store.dart';

void main() {
  test('resource access only authenticates same-origin URLs', () {
    final session = ApiSession(
      origin: 'https://media.example.com/luma/',
      token: 'secret',
    );

    final relative = session.resolveResource('/api/v1/media/1/thumbnail');
    final sameOrigin = session.resolveResource(
      'https://media.example.com/luma/art.jpg',
    );
    final siblingPath = session.resolveResource(
      'https://media.example.com/luma2/art.jpg',
    );
    final parentPath = session.resolveResource(
      'https://media.example.com/api/art.jpg',
    );
    final traversedPath = session.resolveResource(
      'https://media.example.com/luma/../luma2/art.jpg',
    );
    final external = session.resolveResource('https://cdn.example.com/art.jpg');
    final schemeRelative = session.resolveResource('//cdn.example.com/art.jpg');

    expect(
      relative.url,
      'https://media.example.com/luma/api/v1/media/1/thumbnail',
    );
    expect(relative.headers['Authorization'], 'Bearer secret');
    expect(sameOrigin.headers['Authorization'], 'Bearer secret');
    expect(siblingPath.headers, isEmpty);
    expect(parentPath.headers, isEmpty);
    expect(traversedPath.headers, isEmpty);
    expect(external.headers, isEmpty);
    expect(schemeRelative.headers, isEmpty);
    expect(
      session.authorizationHeadersFor('https://media.example.com.evil/art'),
      isEmpty,
    );
    expect(
      session.authorizationHeadersFor(
        'https://media.example.com/luma2/api/v1/media',
      ),
      isEmpty,
    );
  });

  test(
    'stale response is rejected and cannot replace new session cache',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final oldStarted = Completer<void>();
      final releaseOld = Completer<void>();

      server.listen((request) async {
        final authorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        if (authorization == 'Bearer old-token') {
          oldStarted.complete();
          await releaseOld.future;
          await _json(request.response, {
            'items': [_source('old', 'Old source')],
          });
          return;
        }
        await _json(request.response, {
          'items': [_source('new', 'New source')],
        });
      });

      final session = ApiSession(
        origin: 'http://${server.address.host}:${server.port}',
        token: 'old-token',
      );
      final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
      addTearDown(dio.close);
      final repository = ApiSourceRepository(
        ApiClient(dio, apiPrefix: '/custom/'),
      );

      final oldRequest = repository.list(refresh: true);
      await oldStarted.future;
      session.update(origin: session.origin, token: 'new-token');
      final fresh = await repository.list(refresh: true);
      releaseOld.complete();

      expect(fresh.single.name, 'New source');
      await expectLater(
        oldRequest,
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'SESSION_CHANGED',
          ),
        ),
      );
      expect((await repository.list()).single.name, 'New source');
    },
  );

  test(
    'credential failure does not publish candidate and logs it out',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final logoutTokens = <String?>[];
      server.listen((request) async {
        if (request.uri.path.endsWith('/auth/logout')) {
          logoutTokens.add(
            request.headers.value(HttpHeaders.authorizationHeader),
          );
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }
        await _serveConnectionRequest(request, token: 'candidate-token');
      });

      final active = ApiSession(
        origin: 'http://active.example.test',
        token: 'active-token',
      );
      final dio = Dio()..interceptors.add(ApiSessionInterceptor(active));
      addTearDown(dio.close);
      final service = _connectionService(
        dio,
        active,
        _ThrowingCredentialStore(),
      );

      final result = await service.login(
        'http://${server.address.host}:${server.port}',
        const LoginCredentials(username: 'user', password: 'password'),
      );

      expect(result, ConnectionResult.unreachable);
      expect(active.origin, 'http://active.example.test');
      expect(active.token, 'active-token');
      expect(logoutTokens, ['Bearer candidate-token']);
    },
  );

  test(
    'unknown device_key retries once without field, other 400 does not',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bodies = <Map<String, dynamic>>[];
      var rejectUnknownField = true;
      server.listen((request) async {
        if (request.uri.path.endsWith('/auth/login')) {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          bodies.add(Map<String, dynamic>.from(body as Map));
          if (rejectUnknownField && bodies.length == 1) {
            await _json(request.response, {
              'error': {
                'code': 'INVALID_REQUEST',
                'message': 'JSON 请求体无效: unknown field "device_key"',
              },
            }, status: HttpStatus.badRequest);
            return;
          }
        }
        await _serveConnectionRequest(request, token: 'compatible-token');
      });

      final session = ApiSession();
      final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
      addTearDown(dio.close);
      final credentials = _MemoryCredentialStore();
      final service = _connectionService(dio, session, credentials);
      final address = 'http://${server.address.host}:${server.port}';

      expect(
        await service.login(
          address,
          const LoginCredentials(username: 'user', password: 'password'),
        ),
        ConnectionResult.success,
      );
      expect(bodies, hasLength(2));
      expect(bodies.first['device_key'], 'test-device-key');
      expect(bodies.last.containsKey('device_key'), isFalse);

      await service.disconnect();
      bodies.clear();
      rejectUnknownField = false;
      final rejectingServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => rejectingServer.close(force: true));
      rejectingServer.listen((request) async {
        if (request.uri.path.endsWith('/health')) {
          await _json(request.response, {'status': 'ok', 'version': 'legacy'});
          return;
        }
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        bodies.add(Map<String, dynamic>.from(body as Map));
        await _json(request.response, {
          'error': {
            'code': 'INVALID_REQUEST',
            'message': 'password format is invalid',
          },
        }, status: HttpStatus.badRequest);
      });

      expect(
        await service.login(
          'http://${rejectingServer.address.host}:${rejectingServer.port}',
          const LoginCredentials(username: 'user', password: 'password'),
        ),
        ConnectionResult.unreachable,
      );
      expect(bodies, hasLength(1));
      expect(bodies.single['device_key'], 'test-device-key');
    },
  );

  test(
    'disconnect invalidates immediately and cannot erase fast reconnect',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final logoutStarted = Completer<void>();
      final releaseLogout = Completer<void>();
      server.listen((request) async {
        if (request.uri.path.endsWith('/auth/logout')) {
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer old-token',
          );
          logoutStarted.complete();
          await releaseLogout.future;
          request.response.statusCode = HttpStatus.noContent;
          await request.response.close();
          return;
        }
        await _serveConnectionRequest(request, token: 'new-token');
      });

      final origin = 'http://${server.address.host}:${server.port}';
      final session = ApiSession(origin: origin, token: 'old-token');
      final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
      addTearDown(dio.close);
      final credentials = _MemoryCredentialStore();
      final service = _connectionService(dio, session, credentials);

      final disconnect = service.disconnect();
      expect(session.origin, isEmpty);
      expect(session.token, isNull);
      await logoutStarted.future;

      final reconnect = await service.restore(origin, 'new-token');
      expect(reconnect, ConnectionResult.success);
      expect(session.token, 'new-token');
      expect(credentials.current?.sessionToken, 'new-token');

      releaseLogout.complete();
      await disconnect;
      expect(session.token, 'new-token');
      expect(credentials.current?.sessionToken, 'new-token');
    },
  );

  test(
    'credential clear failure still invalidates in-memory session',
    () async {
      final session = ApiSession(
        origin: 'http://server.local:8080',
        token: null,
      );
      final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
      addTearDown(dio.close);
      final credentials = _ClearThrowingCredentialStore();
      final service = _connectionService(dio, session, credentials);
      service.connectedProfile = const ServerProfile(
        name: 'Server',
        address: 'http://server.local:8080',
        token: '',
        hostName: 'server.local',
      );

      final disconnect = service.disconnect();
      expect(session.origin, isEmpty);
      expect(session.token, isNull);
      expect(service.connectedProfile, isNull);
      await expectLater(disconnect, throwsA(isA<StateError>()));
      expect(credentials.clearCalled, isTrue);
    },
  );
}

ApiConnectionService _connectionService(
  Dio dio,
  ApiSession session,
  CredentialStore credentials,
) => ApiConnectionService(
  client: ApiClient(dio, apiPrefix: '/custom/'),
  apiSession: session,
  credentialStore: credentials,
  aliasStore: const _MemoryAliasStore(),
  deviceNameResolver: const _FixedDeviceNameResolver(),
  deviceKeyStore: MemoryDeviceKeyStore(),
);

Future<void> _serveConnectionRequest(
  HttpRequest request, {
  required String token,
}) async {
  final path = request.uri.path;
  if (path.endsWith('/health')) {
    await _json(request.response, {'status': 'ok', 'version': 'dev'});
    return;
  }
  if (path.endsWith('/auth/login')) {
    await _json(request.response, {'session_token': token});
    return;
  }
  if (path.endsWith('/system/info')) {
    await _json(request.response, {
      'version': 'dev',
      'platform': 'test',
      'architecture': 'test',
      'database': 'ok',
      'capabilities': <String>[],
    });
    return;
  }
  if (path.endsWith('/sources')) {
    await _json(request.response, {'items': <Object>[]});
    return;
  }
  request.response.statusCode = HttpStatus.notFound;
  await request.response.close();
}

Map<String, Object?> _source(String id, String name) => {
  'id': id,
  'name': name,
  'type': 'local',
  'library_kind': 'personal',
  'enabled': true,
  'status': 'online',
  'last_scan_id': null,
  'last_seen_at': null,
  'created_at': '2026-01-01T00:00:00.000Z',
  'updated_at': '2026-01-01T00:00:00.000Z',
};

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

final class _MemoryCredentialStore implements CredentialStore {
  StoredCredentials? current;

  @override
  Future<void> clear() async => current = null;

  @override
  Future<StoredCredentials?> read() async => current;

  @override
  Future<void> write(StoredCredentials credentials) async {
    current = credentials;
  }
}

final class _ThrowingCredentialStore implements CredentialStore {
  @override
  Future<void> clear() async {}

  @override
  Future<StoredCredentials?> read() async => null;

  @override
  Future<void> write(StoredCredentials credentials) async {
    throw StateError('secure storage failed');
  }
}

final class _ClearThrowingCredentialStore implements CredentialStore {
  bool clearCalled = false;

  @override
  Future<void> clear() async {
    clearCalled = true;
    throw StateError('secure storage clear failed');
  }

  @override
  Future<StoredCredentials?> read() async => null;

  @override
  Future<void> write(StoredCredentials credentials) async {}
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

final class _FixedDeviceNameResolver implements DeviceNameResolver {
  const _FixedDeviceNameResolver();

  @override
  Future<String> resolve() async => 'Test Device';
}
