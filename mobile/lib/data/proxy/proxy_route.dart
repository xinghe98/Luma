import 'dart:io';

final class ProxyEndpoint {
  const ProxyEndpoint({
    required this.profileId,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  final String profileId;
  final String host;
  final int port;
  final String username;
  final String password;
}

/// 当前进程的动态代理路由。端点与凭据只保存在内存。
final class ProxyRoute {
  ProxyEndpoint? _endpoint;

  ProxyEndpoint? get endpoint => _endpoint;
  bool get isActive => _endpoint != null;

  void activate(ProxyEndpoint endpoint) => _endpoint = endpoint;

  void deactivate() => _endpoint = null;

  String findProxy(Uri uri) {
    final endpoint = _endpoint;
    if (endpoint == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        _isLoopback(uri.host)) {
      return 'DIRECT';
    }
    return 'PROXY ${endpoint.host}:${endpoint.port}';
  }

  Future<bool> authenticateProxy(
    HttpClient client,
    String host,
    int port,
    String scheme,
    String? realm,
  ) async {
    final endpoint = _endpoint;
    if (endpoint == null ||
        host != endpoint.host ||
        port != endpoint.port ||
        scheme.toLowerCase() != 'basic') {
      return false;
    }
    client.addProxyCredentials(
      host,
      port,
      realm ?? '',
      HttpClientBasicCredentials(endpoint.username, endpoint.password),
    );
    return true;
  }

  static bool _isLoopback(String host) {
    if (host.toLowerCase() == 'localhost') return true;
    final address = InternetAddress.tryParse(host);
    return address?.isLoopback ?? false;
  }
}

/// 安装后保留原有 overrides，释放时仅恢复自己替换的全局值。
final class ProxyHttpOverrides extends HttpOverrides {
  ProxyHttpOverrides(this.route, {HttpOverrides? previous})
    : _previous = previous ?? HttpOverrides.current;

  final ProxyRoute route;
  final HttpOverrides? _previous;

  void install() => HttpOverrides.global = this;

  void restore() {
    if (identical(HttpOverrides.current, this)) {
      HttpOverrides.global = _previous;
    }
  }

  HttpClient newClient([SecurityContext? context]) => createHttpClient(context);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        _previous?.createHttpClient(context) ?? super.createHttpClient(context);
    client.findProxy = route.findProxy;
    client.authenticateProxy = (host, port, scheme, realm) =>
        route.authenticateProxy(client, host, port, scheme, realm);
    return client;
  }
}
