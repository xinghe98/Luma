// 本地媒体转发复用代理与认证边界；每个播放 token 固定首次选定的资源地址。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

final class MediaRequestRoute {
  const MediaRequestRoute({
    required this.url,
    required this.headers,
    this.token,
  });

  final String url;
  final Map<String, String> headers;
  final String? token;
}

abstract interface class MediaRequestRouter {
  MediaRequestRoute route(String url, Map<String, String> headers);

  void revoke(String? token);

  void revokeAll();
}

final class DirectMediaRequestRouter implements MediaRequestRouter {
  const DirectMediaRequestRouter();

  @override
  MediaRequestRoute route(String url, Map<String, String> headers) =>
      MediaRequestRoute(url: url, headers: headers);

  @override
  void revoke(String? token) {}

  @override
  void revokeAll() {}
}

typedef MediaAuthorizationResolver = Map<String, String> Function(String url);

final class LoopbackMediaRelay implements MediaRequestRouter {
  /// 创建直连和代理共用的播放转发器；上游路由由注入的 HttpClient 决定。
  LoopbackMediaRelay({
    required HttpClient Function() createHttpClient,
    required MediaAuthorizationResolver authorizationHeadersFor,
    this.responseHeadersTimeout = const Duration(seconds: 60),
  }) : _createHttpClient = createHttpClient,
       _authorizationHeadersFor = authorizationHeadersFor;

  static const _forwardedRequestHeaders = <String>{
    'range',
    'if-range',
    'if-modified-since',
    'if-none-match',
    'accept',
  };
  static const _forwardedResponseHeaders = <String>{
    'content-range',
    'accept-ranges',
    'content-length',
    'content-type',
    'etag',
    'last-modified',
    'cache-control',
  };

  final HttpClient Function() _createHttpClient;
  final MediaAuthorizationResolver _authorizationHeadersFor;

  /// 上游响应头的等待上限；防止首次解析卡住后阻塞同一播放的所有 Range。
  final Duration responseHeadersTimeout;
  final Map<String, _MediaTarget> _targets = {};
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  int get registeredTargetCount => _targets.length;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server = server;
    _subscription = server.listen(_handleRequest, onError: (_) {});
  }

  /// 为一次播放创建独立地址；首次响应选定表示后，后续 Range 不再重选入口。
  @override
  MediaRequestRoute route(String url, Map<String, String> headers) {
    final server = _server;
    final target = Uri.tryParse(url);
    if (server == null ||
        target == null ||
        (target.scheme != 'http' && target.scheme != 'https')) {
      throw StateError('媒体代理入口尚未就绪');
    }
    final token = _randomToken();
    _targets[token] = _MediaTarget(
      uri: target,
      headers: Map<String, String>.unmodifiable(headers),
    );
    return MediaRequestRoute(
      url: 'http://127.0.0.1:${server.port}/media/$token',
      headers: const {},
      token: token,
    );
  }

  @override
  void revoke(String? token) {
    if (token != null) _targets.remove(token);
  }

  @override
  void revokeAll() => _targets.clear();

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await response.close();
      return;
    }
    final segments = request.uri.pathSegments;
    if (segments.length != 2 || segments.first != 'media') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final target = _targets[segments[1]];
    if (target == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final client = _createHttpClient();
    client.autoUncompress = false;
    unawaited(
      response.done.then<void>(
        (_) => client.close(force: true),
        onError: (Object _, StackTrace _) => client.close(force: true),
      ),
    );
    try {
      final upstream = await _openUpstream(
        client: client,
        method: request.method,
        target: target,
        downstreamHeaders: request.headers,
      );
      response.statusCode = upstream.statusCode;
      upstream.headers.forEach((name, values) {
        if (_forwardedResponseHeaders.contains(name.toLowerCase())) {
          response.headers.set(name, values);
        }
      });
      if (request.method == 'HEAD') {
        await response.close();
      } else {
        await response.addStream(upstream);
        await response.close();
      }
    } catch (_) {
      try {
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {
        // 响应头已发送时只能关闭流。
      }
      try {
        await response.close();
      } catch (_) {
        // 客户端已取消时只需终止上游连接。
      }
    } finally {
      client.close(force: true);
    }
  }

  /// 首批并发请求共用一次地址选择，只等响应头，不阻塞已选资源的并行读取。
  Future<HttpClientResponse> _openUpstream({
    required HttpClient client,
    required String method,
    required _MediaTarget target,
    required HttpHeaders downstreamHeaders,
  }) async {
    while (target.resolving != null) {
      await target.resolving!.future;
    }
    final selection = target.resolvedUri == null ? Completer<void>() : null;
    if (selection != null) target.resolving = selection;
    final headerDeadline = Timer(
      responseHeadersTimeout,
      () => client.close(force: true),
    );
    try {
      var uri = target.resolvedUri ?? target.uri;
      var authorizationHeaders = uri == target.uri
          ? target.headers
          : _authorizationHeadersFor(uri.toString());
      var redirectCount = 0;
      while (true) {
        final upstreamRequest = await client.openUrl(method, uri);
        upstreamRequest.followRedirects = false;
        for (final entry in authorizationHeaders.entries) {
          upstreamRequest.headers.set(entry.key, entry.value);
        }
        downstreamHeaders.forEach((name, values) {
          if (_forwardedRequestHeaders.contains(name.toLowerCase())) {
            upstreamRequest.headers.set(name, values);
          }
        });

        final upstream = await upstreamRequest.close();
        if (!upstream.isRedirect) {
          if (selection != null &&
              (upstream.statusCode == HttpStatus.ok ||
                  upstream.statusCode == HttpStatus.partialContent ||
                  upstream.statusCode == HttpStatus.notModified ||
                  upstream.statusCode ==
                      HttpStatus.requestedRangeNotSatisfiable)) {
            target.resolvedUri = uri;
          }
          return upstream;
        }

        await upstream.drain<void>();
        final location = upstream.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.isEmpty || redirectCount >= 5) {
          throw const HttpException('Invalid media redirect');
        }
        final nextUri = uri.resolve(location);
        if (!nextUri.isAbsolute ||
            (nextUri.scheme != 'http' && nextUri.scheme != 'https')) {
          throw const HttpException('Invalid media redirect');
        }
        redirectCount++;
        uri = nextUri;
        authorizationHeaders = _authorizationHeadersFor(uri.toString());
      }
    } finally {
      headerDeadline.cancel();
      if (selection != null) {
        target.resolving = null;
        selection.complete();
      }
    }
  }

  Future<void> close() async {
    revokeAll();
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

final class _MediaTarget {
  _MediaTarget({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
  Uri? resolvedUri;
  Completer<void>? resolving;
}
