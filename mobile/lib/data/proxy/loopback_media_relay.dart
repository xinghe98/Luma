// 本地媒体转发复用代理与认证边界；每个播放 token 固定首次选定的资源地址。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 一次播放请求的路由结果：本地转发地址、固定请求头，以及可选的错误诊断回调。
final class MediaRequestRoute {
  const MediaRequestRoute({
    required this.url,
    required this.headers,
    this.token,
    this.describeFailure,
  });

  final String url;
  final Map<String, String> headers;
  final String? token;

  /// 播放器报错时可读取的诊断快照回调：无副作用，返回一段紧凑的中文摘要，
  /// 只包含失败类别、上游状态码与字节数，不暴露令牌、来源地址或原始异常文本。
  /// 直连路由保持为 null；本地转发路由在 revoke 之后仍可读取最后一次快照。
  final String Function()? describeFailure;
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
  ///
  /// 返回的路由携带 [MediaRequestRoute.describeFailure] 回调：闭包直接持有
  /// 该目标的诊断记录，revoke 之后仍能读取最后一次请求的快照；
  /// 新建路由则从空白状态开始。
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
    final newTarget = _MediaTarget(
      uri: target,
      headers: Map<String, String>.unmodifiable(headers),
    );
    _targets[token] = newTarget;
    return MediaRequestRoute(
      url: 'http://127.0.0.1:${server.port}/media/$token',
      headers: const {},
      token: token,
      describeFailure: newTarget.requestLog.describe,
    );
  }

  @override
  void revoke(String? token) {
    if (token != null) _targets.remove(token);
  }

  @override
  void revokeAll() => _targets.clear();

  /// 处理播放器请求：先登记本次请求的诊断进度，再按原语义转发上游。
  ///
  /// 字节计数随流进行、不复制分块；失败时只把安全类别写入最新请求的快照，
  /// 下游取消与上游故障分别记录，避免把播放器中止的过时 Range 误报为网络根因。
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

    // 登记本次播放器请求；旧请求此后只写回自己的进度，不会覆盖最新快照。
    final progress = target.requestLog.beginRequest();
    final client = _createHttpClient();
    client.autoUncompress = false;
    unawaited(
      response.done.then<void>(
        (_) => client.close(force: true),
        onError: (Object _, StackTrace _) {
          // 无已知上游失败时才视为下游取消（播放器中止过时 Range）；
          // 上游断流已经 handleError 先行登记，不能被误报成播放器取消。
          if (progress.upstreamFailureCategory == null) {
            progress.downstreamCancelled = true;
          }
          client.close(force: true);
        },
      ),
    );
    try {
      final upstream = await _openUpstream(
        client: client,
        method: request.method,
        target: target,
        downstreamHeaders: request.headers,
        progress: progress,
      );
      progress.upstreamStatus = upstream.statusCode;
      response.statusCode = upstream.statusCode;
      upstream.headers.forEach((name, values) {
        if (_forwardedResponseHeaders.contains(name.toLowerCase())) {
          response.headers.set(name, values);
        }
      });
      if (request.method == 'HEAD') {
        await response.close();
      } else {
        // 边读取上游边计数，不复制分块，也不声称字节已送达播放器。
        // 上游流异常先经 handleError 登记类别再继续传播，
        // 保证外层 catch 与下游 done 都能看到真正的根因。
        await response.addStream(
          upstream.transform(
            StreamTransformer<List<int>, List<int>>.fromHandlers(
              handleData: (chunk, sink) {
                progress.upstreamBytes += chunk.length;
                sink.add(chunk);
              },
              handleError: (Object error, StackTrace stack, sink) {
                progress.noteUpstreamError(error);
                sink.addError(error, stack);
              },
            ),
          ),
        );
        await response.close();
      }
    } catch (error) {
      // 已有类别或下游取消时不覆盖，保持先到者的根因记录。
      progress.noteUpstreamError(error);
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
  ///
  /// [progress] 只用于安全诊断：记录响应头等待超时标记与非法重定向标记，
  /// 便于把强关客户端后抛出的连接异常准确归类，而不改变任何超时时长。
  Future<HttpClientResponse> _openUpstream({
    required HttpClient client,
    required String method,
    required _MediaTarget target,
    required HttpHeaders downstreamHeaders,
    required _RouteRequestProgress progress,
  }) async {
    while (target.resolving != null) {
      await target.resolving!.future;
    }
    final selection = target.resolvedUri == null ? Completer<void>() : null;
    if (selection != null) target.resolving = selection;
    final headerDeadline = Timer(responseHeadersTimeout, () {
      // 先标记再强关客户端：随后抛出的连接异常需归类为响应头等待超时。
      progress.headerTimeoutFired = true;
      client.close(force: true);
    });
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
        Uri? nextUri;
        if (location != null && location.isNotEmpty && redirectCount < 5) {
          try {
            nextUri = uri.resolve(location);
          } on FormatException {
            nextUri = null;
          }
        }
        if (nextUri == null ||
            !nextUri.isAbsolute ||
            (nextUri.scheme != 'http' && nextUri.scheme != 'https')) {
          progress.invalidRedirect = true;
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

  /// 每条路由自带的诊断记录；路由回调闭包直接持有它，revoke 后仍可读取。
  final _RouteRequestLog requestLog = _RouteRequestLog();
  Uri? resolvedUri;
  Completer<void>? resolving;
}

/// 单条路由的请求进度记录；describeFailure 闭包直接持有它，
/// revoke 之后仍可读取最后一次请求的快照，新建路由则从空白开始。
final class _RouteRequestLog {
  _RouteRequestProgress? _latest;

  /// 播放器请求进入转发器时登记；返回独立进度对象，
  /// 并发旧请求结束后只会写回自己的对象，不会覆盖最新一次请求的快照。
  _RouteRequestProgress beginRequest() {
    final progress = _RouteRequestProgress();
    _latest = progress;
    return progress;
  }

  /// 生成最近一次请求的中文摘要；只读无副作用，可直接拼入错误提示。
  String describe() {
    final progress = _latest;
    if (progress == null) return '尚未收到播放器请求';
    final parts = <String>[];
    if (progress.downstreamCancelled) {
      parts.add('播放器已取消该请求');
    } else if (progress.upstreamFailureCategory != null) {
      parts.add('上游传输失败：${progress.upstreamFailureCategory}');
    } else if (progress.upstreamStatus == null) {
      parts.add('正在等待上游响应头');
    }
    if (progress.upstreamStatus != null) {
      parts.add('上游 HTTP ${progress.upstreamStatus}');
    }
    if (progress.upstreamBytes > 0) {
      parts.add('已从上游读取 ${_formatBytes(progress.upstreamBytes)}');
    }
    return parts.join('，');
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '$bytes 字节';
  }
}

/// 单次播放器请求的可展示诊断状态；只保留类别、状态码与字节数。
final class _RouteRequestProgress {
  int? upstreamStatus;
  int upstreamBytes = 0;
  bool headerTimeoutFired = false;
  bool invalidRedirect = false;
  bool downstreamCancelled = false;
  String? upstreamFailureCategory;

  /// 在上游流异常继续传播前登记安全类别；已标记下游取消时不覆盖根因，
  /// 避免把真正的上游断流误报成播放器取消（或反之）。
  void noteUpstreamError(Object error) {
    if (!downstreamCancelled && upstreamFailureCategory == null) {
      upstreamFailureCategory = failureCategoryFor(error);
    }
  }

  /// 依据异常类型与本请求已记录的标记归类失败原因；
  /// 不读取异常文本，仅保留数值型系统错误码。
  String failureCategoryFor(Object error) {
    if (headerTimeoutFired) return '上游响应头等待超时';
    if (invalidRedirect) return '重定向地址无效';
    if (error is TlsException) return 'TLS 握手失败';
    if (error is SocketException) {
      final osCode = error.osError?.errorCode;
      return osCode == null ? '上游连接失败' : '上游连接失败（系统错误码 $osCode）';
    }
    return '上游传输异常';
  }
}
