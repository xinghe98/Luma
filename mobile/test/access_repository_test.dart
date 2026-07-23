import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/api/api_client.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/api/api_session_interceptor.dart';
import 'package:luma/data/repositories/api_access_repository.dart';

void main() {
  test(
    'access repository maps administrator users, tokens and grants',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <String>[];

      server.listen((request) async {
        final key = '${request.method} ${request.uri.path}';
        requests.add(key);
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer admin-token',
        );
        switch (key) {
          case 'GET /api/v1/admin/users':
            await _json(request.response, {
              'items': [_user(id: 'member-1', name: 'Alice')],
            });
            return;
          case 'POST /api/v1/admin/users':
            final body = await _body(request);
            expect(body, {'name': 'Alice'});
            await _json(request.response, _user(id: 'member-1', name: 'Alice'));
            return;
          case 'PATCH /api/v1/admin/users/member-1':
            final body = await _body(request);
            expect(body, {'name': 'Alice Wu', 'enabled': false});
            await _json(
              request.response,
              _user(id: 'member-1', name: 'Alice Wu', enabled: false),
            );
            return;
          case 'GET /api/v1/admin/users/member-1/tokens':
            await _json(request.response, {
              'items': [_token(id: 'token-1')],
            });
            return;
          case 'POST /api/v1/admin/users/member-1/tokens':
            final body = await _body(request);
            expect(body['name'], 'Alice phone');
            expect(
              DateTime.parse(body['expires_at'] as String),
              DateTime.utc(2026, 8, 1),
            );
            await _json(request.response, {
              ..._token(id: 'token-2'),
              'token': 'only-returned-once',
            });
            return;
          case 'DELETE /api/v1/admin/tokens/token-1':
          case 'PUT /api/v1/admin/users/member-1/sources/source-1':
          case 'DELETE /api/v1/admin/users/member-1/sources/source-1':
            request.response.statusCode = HttpStatus.noContent;
            await request.response.close();
            return;
          case 'GET /api/v1/admin/users/member-1/sources':
            await _json(request.response, {
              'source_ids': ['source-1', 'source-2'],
            });
            return;
          default:
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
        }
      });

      final session = ApiSession(
        origin: 'http://${server.address.host}:${server.port}',
        token: 'admin-token',
      );
      final dio = Dio()..interceptors.add(ApiSessionInterceptor(session));
      addTearDown(dio.close);
      final repository = ApiAccessRepository(ApiClient(dio));

      final users = await repository.listUsers();
      final created = await repository.createUser('Alice');
      final updated = await repository.updateUser(
        created.id,
        name: 'Alice Wu',
        enabled: false,
      );
      final tokens = await repository.listTokens(created.id);
      final issued = await repository.issueToken(
        created.id,
        name: 'Alice phone',
        expiresAt: DateTime.utc(2026, 8, 1),
      );
      final grants = await repository.listGrants(created.id);
      await repository.grantSource(created.id, 'source-1');
      await repository.revokeSource(created.id, 'source-1');
      await repository.revokeToken(tokens.single.id);

      expect(users.single.name, 'Alice');
      expect(updated.enabled, isFalse);
      expect(issued.token, 'only-returned-once');
      expect(grants, ['source-1', 'source-2']);
      expect(requests, [
        'GET /api/v1/admin/users',
        'POST /api/v1/admin/users',
        'PATCH /api/v1/admin/users/member-1',
        'GET /api/v1/admin/users/member-1/tokens',
        'POST /api/v1/admin/users/member-1/tokens',
        'GET /api/v1/admin/users/member-1/sources',
        'PUT /api/v1/admin/users/member-1/sources/source-1',
        'DELETE /api/v1/admin/users/member-1/sources/source-1',
        'DELETE /api/v1/admin/tokens/token-1',
      ]);
    },
  );
}

Future<Map<String, dynamic>> _body(HttpRequest request) async =>
    Map<String, dynamic>.from(
      jsonDecode(await utf8.decoder.bind(request).join()) as Map,
    );

Future<void> _json(HttpResponse response, Object body) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  await response.close();
}

Map<String, Object?> _user({
  required String id,
  required String name,
  bool enabled = true,
}) => {
  'id': id,
  'name': name,
  'role': 'member',
  'enabled': enabled,
  'created_at': '2026-07-01T00:00:00Z',
  'updated_at': '2026-07-01T00:00:00Z',
};

Map<String, Object?> _token({required String id}) => {
  'id': id,
  'user_id': 'member-1',
  'name': 'Alice phone',
  'token_prefix': 'luma_abc',
  'expires_at': null,
  'revoked_at': null,
  'created_at': '2026-07-01T00:00:00Z',
};
