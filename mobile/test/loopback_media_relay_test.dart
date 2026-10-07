import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/proxy/loopback_media_relay.dart';

void main() {
  late HttpServer upstream;
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
    relay = LoopbackMediaRelay(
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

  test('GET forwards auth and range then streams 206 metadata', () async {
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

  test(
    'redirect via proxy that drops reused connections still streams media',
    () async {
      // 模拟 Xray http 入站：响应头声称 keep-alive，回完一个响应后却不再处理
      // 同一连接上的请求，稍后直接断开。
      final targets = <String>[];
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(proxy.close);
      proxy.listen((socket) {
        socket.done.ignore();
        final head = <int>[];
        var answered = false;
        socket.listen((chunk) {
          if (answered) return;
          head.addAll(chunk);
          final text = latin1.decode(head, allowInvalid: true);
          if (!text.contains('\r\n\r\n')) return;
          answered = true;
          final target = Uri.parse(text.split(' ')[1]);
          targets.add(target.path);
          if (target.path == '/luma/entry') {
            socket.add(
              latin1.encode(
                'HTTP/1.1 302 Found\r\nLocation: final\r\n'
                'Content-Length: 0\r\nConnection: keep-alive\r\n\r\n',
              ),
            );
          } else {
            socket
              ..add(
                latin1.encode(
                  'HTTP/1.1 200 OK\r\n'
                  'Content-Type: application/octet-stream\r\n'
                  'Content-Length: ${media.length}\r\n'
                  'Connection: keep-alive\r\n\r\n',
                ),
              )
              ..add(media);
          }
          Timer(const Duration(milliseconds: 100), socket.destroy);
        }, onError: (Object _) {});
      });
      await relay.close();
      relay = LoopbackMediaRelay(
        createHttpClient: () =>
            HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:${proxy.port}',
        authorizationHeadersFor: (_) => const {},
      );
      await relay.start();
      final route = relay.route('http://192.0.2.10:8081/luma/entry', const {});
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() => client.close(force: true));

      final response = await (await client.getUrl(
        Uri.parse(route.url),
      )).close();

      expect(response.statusCode, HttpStatus.ok);
      expect(utf8.decode(await _body(response)), '0123456789');
      expect(targets, ['/luma/entry', '/luma/final']);
    },
  );

  test(
    'one playback pins its representation across concurrent ranges',
    () async {
      final selected = Completer<void>();
      final release = Completer<void>();
      var warmed = false;
      var removed = false;
      var entries = 0;
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      origin.listen((request) async {
        final response = request.response;
        if (request.uri.path == '/stream') {
          entries++;
          final location = warmed ? '/cached' : '/source';
          if (!selected.isCompleted) {
            selected.complete();
            await release.future;
          }
          response
            ..statusCode = HttpStatus.found
            ..headers.set(HttpHeaders.locationHeader, location);
        } else if (removed) {
          response.statusCode = HttpStatus.notFound;
        } else {
          final body = request.uri.path == '/source' ? '2345' : 'abcd';
          expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=2-5');
          response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 2-5/10')
            ..contentLength = 4;
          if (request.method != 'HEAD') response.write(body);
        }
        await response.close();
      });
      final route = relay.route(
        'http://127.0.0.1:${origin.port}/stream',
        const {},
      );
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() => client.close(force: true));

      Future<HttpClientResponse> requestRange(String method) async {
        final request = await client.openUrl(method, Uri.parse(route.url));
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
        return request.close();
      }

      final first = requestRange('HEAD');
      await selected.future;
      warmed = true;
      final concurrent = requestRange('GET');
      release.complete();
      final head = await first;
      expect(head.statusCode, HttpStatus.partialContent);
      expect(head.contentLength, 4);
      expect(await _body(head), isEmpty);
      final overlappingRange = await concurrent;
      expect(utf8.decode(await _body(overlappingRange)), '2345');
      final laterRange = await requestRange('GET');
      expect(utf8.decode(await _body(laterRange)), '2345');
      expect(entries, 1);

      removed = true;
      final missing = await requestRange('GET');
      expect(missing.statusCode, HttpStatus.notFound);
      await _body(missing);
      expect(entries, 1, reason: '已选表示失效不能回入口改选另一种字节布局');
    },
  );

  for (final cancelFirst in [false, true]) {
    test(
      'stalled initial headers release queued Range (cancel=$cancelFirst)',
      () async {
        final entered = Completer<void>();
        var requests = 0;
        final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => origin.close(force: true));
        origin.listen((request) async {
          requests++;
          if (requests == 1) {
            entered.complete();
            return;
          }
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 2-5/10')
            ..contentLength = 4
            ..write('2345');
          await request.response.close();
        });
        await relay.close();
        relay = LoopbackMediaRelay(
          createHttpClient: () => HttpClient()..findProxy = (_) => 'DIRECT',
          authorizationHeadersFor: (_) => const {},
          responseHeadersTimeout: const Duration(milliseconds: 150),
        );
        await relay.start();
        final route = relay.route(
          'http://127.0.0.1:${origin.port}/stream',
          const {},
        );
        final firstClient = HttpClient()..findProxy = (_) => 'DIRECT';
        final nextClient = HttpClient()..findProxy = (_) => 'DIRECT';
        addTearDown(() {
          firstClient.close(force: true);
          nextClient.close(force: true);
        });
        final first = await firstClient.getUrl(Uri.parse(route.url));
        final outcome = first.close().then<int>((response) async {
          await response.drain<void>();
          return response.statusCode;
        }, onError: (Object _) => -1);
        await entered.future;
        if (cancelFirst) first.abort();
        final next = await nextClient.getUrl(Uri.parse(route.url));
        next.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
        final response = await next.close().timeout(const Duration(seconds: 2));
        expect(response.statusCode, HttpStatus.partialContent);
        expect(utf8.decode(await _body(response)), '2345');
        expect(await outcome, cancelFirst ? -1 : HttpStatus.badGateway);
        expect(requests, 2);
      },
    );
  }

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

  test('401 metadata and 206 bytes produce distinct snapshots', () async {
    final deny = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => deny.close(force: true));
    deny.listen((request) async {
      // 只回 401 状态，不带响应体，观察快照是否只记录状态而不虚报字节。
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));

    final deniedRoute = relay.route(
      'http://127.0.0.1:${deny.port}/video',
      const {},
    );
    final deniedResponse = await (await client.getUrl(
      Uri.parse(deniedRoute.url),
    )).close();
    expect(deniedResponse.statusCode, HttpStatus.unauthorized);
    await _body(deniedResponse);
    final deniedSnapshot = deniedRoute.describeFailure!();
    expect(deniedSnapshot, contains('HTTP 401'));
    expect(deniedSnapshot, isNot(contains('字节')));
    _expectSafeSnapshot(deniedSnapshot);

    final mediaRoute = relay.route(
      'http://127.0.0.1:${upstream.port}/video',
      const {},
    );
    final mediaRequest = await client.getUrl(Uri.parse(mediaRoute.url));
    mediaRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
    final mediaResponse = await mediaRequest.close();
    expect(mediaResponse.statusCode, HttpStatus.partialContent);
    expect(utf8.decode(await _body(mediaResponse)), '2345');
    final mediaSnapshot = mediaRoute.describeFailure!();
    expect(mediaSnapshot, contains('HTTP 206'));
    expect(mediaSnapshot, contains('4 字节'));
    _expectSafeSnapshot(mediaSnapshot);
  });

  test(
    'connection refused reports upstream failure without addresses',
    () async {
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = dead.port;
      await dead.close(force: true);

      final route = relay.route('http://127.0.0.1:$deadPort/video', const {});
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() => client.close(force: true));
      final snapshotBefore = route.describeFailure!();
      expect(snapshotBefore, contains('尚未'));

      final response = await (await client.getUrl(
        Uri.parse(route.url),
      )).close();
      expect(response.statusCode, HttpStatus.badGateway);
      await _body(response);

      final snapshot = route.describeFailure!();
      expect(snapshot, isNot(contains('尚未')));
      expect(snapshot, contains('连接失败'));
      expect(snapshot, isNot(contains('取消')));
      expect(snapshot, isNot(contains('$deadPort')));
      _expectSafeSnapshot(snapshot);
    },
  );

  test('timed-out upstream headers are classified as timeout', () async {
    final stalled = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => stalled.close(force: true));
    stalled.listen((request) async {
      // 收到请求但不返回响应，让转发器的响应头等待超时触发。
    });
    await relay.close();
    relay = LoopbackMediaRelay(
      createHttpClient: () => HttpClient()..findProxy = (_) => 'DIRECT',
      authorizationHeadersFor: (_) => const {},
      responseHeadersTimeout: const Duration(milliseconds: 150),
    );
    await relay.start();

    final route = relay.route(
      'http://127.0.0.1:${stalled.port}/video',
      const {},
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(Uri.parse(route.url))).close();
    expect(response.statusCode, HttpStatus.badGateway);
    await _body(response);

    final snapshot = route.describeFailure!();
    expect(snapshot, contains('超时'));
    expect(snapshot, isNot(contains('尚未')));
    expect(snapshot, isNot(contains('取消')));
    _expectSafeSnapshot(snapshot);
  });

  test(
    'older failed range does not overwrite snapshot of newer range',
    () async {
      var requests = 0;
      final rangeArrived = Completer<void>();
      final releaseRange = Completer<void>();
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      origin.listen((request) async {
        requests++;
        if (requests == 1) {
          // 首次请求成功返回全量，让该路由固定表示。
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
            ..headers.contentType = ContentType.binary
            ..contentLength = media.length;
          if (request.method != 'HEAD') request.response.add(media);
          await request.response.close();
          return;
        }
        if (requests == 2) {
          // 挂起较旧的 Range A，等较新的 Range B 完成后再断开其连接。
          rangeArrived.complete();
          await releaseRange.future;
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
          return;
        }
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 2-5/10')
          ..headers.contentType = ContentType.binary
          ..contentLength = 4;
        if (request.method != 'HEAD') request.response.write('2345');
        await request.response.close();
      });
      final route = relay.route(
        'http://127.0.0.1:${origin.port}/stream',
        const {},
      );
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() => client.close(force: true));

      // 先成功 warm/pin 同一表示，使后续 Range 不再互相等待地址选择。
      final warm = await client.getUrl(Uri.parse(route.url));
      expect(utf8.decode(await _body(await warm.close())), '0123456789');

      // Range A：上游挂起（已到达 origin），此时登记的快照随即被 B 取代。
      final requestA = await client.getUrl(Uri.parse(route.url));
      requestA.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
      final outcomeA = requestA.close().then<int>((response) async {
        await response.drain<void>();
        return response.statusCode;
      }, onError: (Object _) => -1);
      await rangeArrived.future;

      // Range B：在 A 挂起期间正常完成。
      final requestB = await client.getUrl(Uri.parse(route.url));
      requestB.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
      final responseB = await requestB.close().timeout(
        const Duration(seconds: 2),
      );
      expect(responseB.statusCode, HttpStatus.partialContent);
      expect(utf8.decode(await _body(responseB)), '2345');

      // 释放 A：其失败发生在 B 完成之后（乱序），快照必须仍是 B 的。
      releaseRange.complete();
      expect(await outcomeA, HttpStatus.badGateway);

      final snapshot = route.describeFailure!();
      expect(snapshot, contains('HTTP 206'));
      expect(snapshot, contains('4 字节'));
      expect(snapshot, isNot(contains('失败')));
      expect(snapshot, isNot(contains('超时')));
      _expectSafeSnapshot(snapshot);
    },
  );

  test(
    'truncated upstream body is not reported as player cancellation',
    () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => origin.close(force: true));
      origin.listen((request) async {
        // 声明 Content-Length 100 只发送 40 字节后销毁连接，模拟上游断流。
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n'
          'Content-Length: 100\r\nConnection: close\r\n\r\n',
        );
        socket.add(List<int>.filled(40, 7));
        await socket.flush();
        socket.destroy();
      });
      final route = relay.route(
        'http://127.0.0.1:${origin.port}/stream',
        const {},
      );
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(route.url),
      )).close();
      expect(response.statusCode, HttpStatus.ok);
      final ended = Completer<void>();
      late StreamSubscription<List<int>> subscription;
      subscription = response.listen(
        (_) {},
        onError: (Object _) {
          if (!ended.isCompleted) ended.complete();
          unawaited(subscription.cancel());
        },
        onDone: () {
          if (!ended.isCompleted) ended.complete();
        },
      );
      await ended.future.timeout(const Duration(seconds: 2));
      client.close(force: true);
      // 等待转发器两侧（下游 done、上游读取）都结束后再读取快照。
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final snapshot = route.describeFailure!();
      expect(snapshot, contains('失败'));
      expect(snapshot, isNot(contains('取消')));
      expect(snapshot, contains('40 字节'));
      _expectSafeSnapshot(snapshot);
    },
  );

  test('snapshot survives revoke while fresh route starts clean', () async {
    final route = relay.route(
      'http://127.0.0.1:${upstream.port}/video',
      const {},
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(Uri.parse(route.url));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=2-5');
    final response = await request.close();
    expect(utf8.decode(await _body(response)), '2345');
    expect(route.describeFailure!(), contains('HTTP 206'));

    relay.revoke(route.token);
    final revoked = await client.getUrl(Uri.parse(route.url));
    expect((await revoked.close()).statusCode, HttpStatus.notFound);

    // 回调由路由闭包持有，revoke 后仍能读取最后一次快照。
    final snapshot = route.describeFailure!();
    expect(snapshot, contains('HTTP 206'));
    _expectSafeSnapshot(snapshot);

    final freshRoute = relay.route(
      'http://127.0.0.1:${upstream.port}/video',
      const {},
    );
    final freshSnapshot = freshRoute.describeFailure!();
    expect(freshSnapshot, contains('尚未'));
    expect(freshSnapshot, isNot(contains('206')));
    _expectSafeSnapshot(freshSnapshot);
  });

  test('player cancellation is not reported as upstream failure', () async {
    final route = relay.route(
      'http://127.0.0.1:${upstream.port}/slow',
      const {},
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
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
    await relay.close();
    await Future<void>.delayed(Duration.zero);

    final snapshot = route.describeFailure!();
    expect(snapshot, isNot(contains('失败')));
    expect(snapshot, isNot(contains('超时')));
    _expectSafeSnapshot(snapshot);
  });
}

Future<List<int>> _body(HttpClientResponse response) {
  return response.fold<List<int>>(<int>[], (body, chunk) {
    body.addAll(chunk);
    return body;
  });
}

void _expectSafeSnapshot(String snapshot) {
  // 快照不得暴露令牌、入口地址或转发路径等敏感信息。
  expect(snapshot, isNot(contains('127.0.0.1')));
  expect(snapshot, isNot(contains('Bearer')));
  expect(snapshot, isNot(contains('/media')));
  expect(snapshot, isNot(contains('token')));
}
