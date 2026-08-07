import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/proxy/loopback_media_relay.dart';
import 'package:luma/data/proxy/proxy_route.dart';

void main() {
  late HttpServer upstream;
  late ProxyRoute proxyRoute;
  late LoopbackMediaRelay relay;
  late MediaAuthorizationResolver authorizationResolver;
  final requestHeaders = <String, String?>{};
  final media = utf8.encode('0123456789');

  setUp(() async {
    requestHeaders.clear();
    authorizationResolver = (_) => const {};
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      requestHeaders['authorization'] = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      if (request.uri.path == '/slow') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary;
        try {
          for (var index = 0; index < 100; index++) {
            request.response.add(List<int>.filled(1024, index));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        } catch (_) {
          // Relay client cancellation closes the upstream response.
        }
        await request.response.close();
        return;
      }
      requestHeaders['range'] = request.headers.value(HttpHeaders.rangeHeader);
      requestHeaders['x-secret'] = request.headers.value('x-secret');
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range == 'bytes=2-5') {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 2-5/10')
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.contentType = ContentType.binary
          ..contentLength = 4;
        if (request.method != 'HEAD') request.response.add(media.sublist(2, 6));
      } else {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.contentType = ContentType.binary
          ..contentLength = media.length;
        if (request.method != 'HEAD') request.response.add(media);
      }
      await request.response.close();
    });
    proxyRoute = ProxyRoute();
    relay = LoopbackMediaRelay(
      proxyRoute: proxyRoute,
      authorizationHeadersFor: (url) => authorizationResolver(url),
      createHttpClient: () {
        final client = HttpClient()..findProxy = (_) => 'DIRECT';
        return client;
      },
    );
    await relay.start();
  });

  tearDown(() async {
    await relay.close();
    await upstream.close(force: true);
  });

  test('inactive route keeps original media URL and headers', () {
    final original = 'http://127.0.0.1:${upstream.port}/video';
    final route = relay.route(original, const {
      'Authorization': 'Bearer token',
    });
    expect(route.url, original);
    expect(route.headers, {'Authorization': 'Bearer token'});
    expect(route.token, isNull);
  });

  test('GET forwards auth and range then streams 206 metadata', () async {
    _activate(proxyRoute);
    final route = relay.route('http://127.0.0.1:${upstream.port}/video', const {
      'Authorization': 'Bearer token',
    });
    expect(Uri.parse(route.url).host, '127.0.0.1');
    expect(route.headers, isEmpty);

    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final request = await client.getUrl(Uri.parse(route.url));
    request.headers
      ..set(HttpHeaders.rangeHeader, 'bytes=2-5')
      ..set('x-secret', 'must-not-forward');
    final response = await request.close();
    final body = await response.fold<List<int>>(<int>[], (all, chunk) {
      all.addAll(chunk);
      return all;
    });

    expect(response.statusCode, HttpStatus.partialContent);
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 2-5/10',
    );
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(utf8.decode(body), '2345');
    expect(requestHeaders, {
      'authorization': 'Bearer token',
      'range': 'bytes=2-5',
      'x-secret': null,
    });
    client.close(force: true);
  });

  test('HEAD forwards metadata without a response body', () async {
    _activate(proxyRoute);
    final route = relay.route('http://127.0.0.1:${upstream.port}/video', const {
      'Authorization': 'Bearer token',
    });
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final request = await client.headUrl(Uri.parse(route.url));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
    final response = await request.close();
    final body = await response.fold<List<int>>(<int>[], (all, chunk) {
      all.addAll(chunk);
      return all;
    });

    expect(response.statusCode, HttpStatus.partialContent);
    expect(response.contentLength, 4);
    expect(body, isEmpty);
    client.close(force: true);
  });

  test('unknown and revoked tokens return 404', () async {
    _activate(proxyRoute);
    final route = relay.route(
      'http://127.0.0.1:${upstream.port}/video',
      const {},
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final unknown = await client.getUrl(
      Uri.parse(route.url).replace(path: '/media/unknown'),
    );
    expect((await unknown.close()).statusCode, HttpStatus.notFound);

    relay.revoke(route.token);
    final revoked = await client.getUrl(Uri.parse(route.url));
    expect((await revoked.close()).statusCode, HttpStatus.notFound);
    client.close(force: true);
  });

  test('client cancellation closes a streaming relay request', () async {
    _activate(proxyRoute);
    final route = relay.route(
      'http://127.0.0.1:${upstream.port}/slow',
      const {},
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final response = await (await client.getUrl(Uri.parse(route.url))).close();
    final firstChunk = Completer<void>();
    late StreamSubscription<List<int>> subscription;
    subscription = response.listen((_) {
      if (!firstChunk.isCompleted) {
        firstChunk.complete();
        unawaited(subscription.cancel());
      }
    });
    await firstChunk.future.timeout(const Duration(seconds: 2));
    client.close(force: true);
    await relay.close().timeout(const Duration(seconds: 2));
  });

  test('non-GET methods are rejected', () async {
    _activate(proxyRoute);
    final route = relay.route(
      'http://127.0.0.1:${upstream.port}/video',
      const {},
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final request = await client.postUrl(Uri.parse(route.url));
    final response = await request.close();
    expect(response.statusCode, HttpStatus.methodNotAllowed);
    expect(response.headers.value(HttpHeaders.allowHeader), 'GET, HEAD');
    client.close(force: true);
  });

  test(
    'relative 302 and 307 redirects preserve method, range, and auth',
    () async {
      final observed =
          <({String path, String method, String? auth, String? range})>[];
      final redirectServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => redirectServer.close(force: true));
      redirectServer.listen((request) async {
        observed.add((
          path: request.uri.path,
          method: request.method,
          auth: request.headers.value(HttpHeaders.authorizationHeader),
          range: request.headers.value(HttpHeaders.rangeHeader),
        ));
        if (request.uri.path == '/luma/get') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, 'final');
        } else if (request.uri.path == '/luma/head') {
          request.response
            ..statusCode = HttpStatus.temporaryRedirect
            ..headers.set(HttpHeaders.locationHeader, '/luma/final');
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.binary
            ..contentLength = media.length;
          if (request.method != 'HEAD') request.response.add(media);
        }
        await request.response.close();
      });
      final session = ApiSession(
        origin: 'http://127.0.0.1:${redirectServer.port}/luma',
        token: 'token',
      );
      authorizationResolver = session.authorizationHeadersFor;
      _activate(proxyRoute);
      final client = HttpClient()..findProxy = (_) => 'DIRECT';

      final getTarget = 'http://127.0.0.1:${redirectServer.port}/luma/get';
      final getRoute = relay.route(
        getTarget,
        session.authorizationHeadersFor(getTarget),
      );
      final getRequest = await client.getUrl(Uri.parse(getRoute.url));
      getRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
      final getResponse = await getRequest.close();
      expect(utf8.decode(await _body(getResponse)), '0123456789');

      final headTarget = 'http://127.0.0.1:${redirectServer.port}/luma/head';
      final headRoute = relay.route(
        headTarget,
        session.authorizationHeadersFor(headTarget),
      );
      final headResponse = await (await client.headUrl(
        Uri.parse(headRoute.url),
      )).close();
      expect(await _body(headResponse), isEmpty);

      expect(observed, [
        (
          path: '/luma/get',
          method: 'GET',
          auth: 'Bearer token',
          range: 'bytes=2-5',
        ),
        (
          path: '/luma/final',
          method: 'GET',
          auth: 'Bearer token',
          range: 'bytes=2-5',
        ),
        (path: '/luma/head', method: 'HEAD', auth: 'Bearer token', range: null),
        (
          path: '/luma/final',
          method: 'HEAD',
          auth: 'Bearer token',
          range: null,
        ),
      ]);
      client.close(force: true);
    },
  );

  test('redirects outside API authorization boundaries omit bearer', () async {
    final publicAuthorization = <String, String?>{};
    final external = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => external.close(force: true));
    external.listen((request) async {
      publicAuthorization['port'] = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      request.response
        ..contentLength = 6
        ..write('public');
      await request.response.close();
    });
    final origin = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    addTearDown(() => origin.close(force: true));
    origin.listen((request) async {
      if (request.uri.path == '/luma/host') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://localhost:${origin.port}/public-host',
          );
      } else if (request.uri.path == '/luma/port') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${external.port}/public',
          );
      } else if (request.uri.path == '/luma/path') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/public-path');
      } else {
        publicAuthorization[request.uri.path] = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        request.response
          ..contentLength = 6
          ..write('public');
      }
      await request.response.close();
    });
    final session = ApiSession(
      origin: 'http://127.0.0.1:${origin.port}/luma',
      token: 'token',
    );
    authorizationResolver = session.authorizationHeadersFor;
    _activate(proxyRoute);
    final client = HttpClient()..findProxy = (_) => 'DIRECT';

    for (final boundary in ['host', 'port', 'path']) {
      final target = 'http://127.0.0.1:${origin.port}/luma/$boundary';
      final route = relay.route(
        target,
        session.authorizationHeadersFor(target),
      );
      final response = await (await client.getUrl(
        Uri.parse(route.url),
      )).close();
      expect(utf8.decode(await _body(response)), 'public');
    }

    expect(publicAuthorization, {
      '/public-host': null,
      'port': null,
      '/public-path': null,
    });
    expect(
      session.authorizationHeadersFor(
        'https://127.0.0.1:${origin.port}/luma/public',
      ),
      isEmpty,
      reason: 'scheme changes use the same resolver boundary',
    );
    client.close(force: true);
  });

  test(
    'invalid and excessive redirects return 502 after closing responses',
    () async {
      var completedRedirectResponses = 0;
      final invalidServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => invalidServer.close(force: true));
      invalidServer.listen((request) async {
        final path = request.uri.path;
        request.response.statusCode = HttpStatus.found;
        if (path == '/illegal') {
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'http://[invalid',
          );
        } else if (path == '/non-http') {
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'file:///private/media',
          );
        } else if (path == '/loop') {
          request.response.headers.set(HttpHeaders.locationHeader, '/loop');
        } else if (path.startsWith('/chain/')) {
          final step = int.parse(path.split('/').last);
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/chain/${step + 1}',
          );
        }
        request.response.add(utf8.encode('redirect-body'));
        unawaited(
          request.response.done.then((_) {
            completedRedirectResponses++;
          }),
        );
        await request.response.close();
      });
      _activate(proxyRoute);
      final client = HttpClient()..findProxy = (_) => 'DIRECT';

      for (final path in [
        'missing',
        'illegal',
        'non-http',
        'loop',
        'chain/0',
      ]) {
        final target = 'http://127.0.0.1:${invalidServer.port}/$path';
        final route = relay.route(target, const {});
        final response = await (await client.getUrl(
          Uri.parse(route.url),
        )).close();
        expect(response.statusCode, HttpStatus.badGateway, reason: path);
        await _body(response);
      }
      await Future<void>.delayed(Duration.zero);
      expect(completedRedirectResponses, 15);
      client.close(force: true);
    },
  );
}

void _activate(ProxyRoute route) {
  route.activate(
    const ProxyEndpoint(
      profileId: 'profile',
      host: '127.0.0.1',
      port: 1,
      username: 'user',
      password: 'password',
    ),
  );
}

Future<List<int>> _body(HttpClientResponse response) {
  return response.fold<List<int>>(<int>[], (body, chunk) {
    body.addAll(chunk);
    return body;
  });
}
