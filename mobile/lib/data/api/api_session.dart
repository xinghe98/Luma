/// ApiSession 保存当前服务凭据，并用 epoch 隔离会话切换前后的请求。
final class ApiSession {
  /// 创建未连接或指定 origin/token 的会话；初始 epoch 为零。
  ApiSession({String origin = '', String? token})
    : _origin = _normalizeOrigin(origin),
      _token = token;

  String _origin;
  String? _token;
  int _epoch = 0;

  /// 当前服务 origin，可能包含反向代理路径前缀。
  String get origin => _origin;

  /// 当前可撤销会话 token；未连接时为空。
  String? get token => _token;

  /// 会话切换代数，用于拒绝旧请求和旧缓存写入。
  int get epoch => _epoch;

  /// 当前 token 的 Bearer 头；调用方仍须先确认目标地址同源。
  Map<String, String> get authorizationHeaders =>
      _token == null || _token!.isEmpty
      ? const {}
      : {'Authorization': 'Bearer $_token'};

  /// 将服务端相对资源路径拼到当前 origin，且保留反向代理前缀。
  /// 后端返回的资源路径以 `/api/...` 开头。`Uri.resolve` 会把它当作
  /// host 根路径，从而丢掉诸如 `https://host/luma` 中的 `/luma` 前缀。
  String resolve(String path) => resolveResource(path).url;

  /// 解析媒体资源地址，只为同源且位于服务路径前缀内的 HTTP(S) 地址附加认证头。
  /// 外部地址、相邻反向代理路径和非 HTTP(S) 地址始终返回空认证头。
  ApiResourceAccess resolveResource(String path) {
    final target = Uri.tryParse(path);
    if (_origin.isEmpty || target == null) {
      return ApiResourceAccess(url: path, headers: const {});
    }

    final originUri = Uri.tryParse(_origin);
    if (originUri == null) {
      return ApiResourceAccess(url: path, headers: const {});
    }
    final resolved = target.hasScheme || target.hasAuthority
        ? originUri.resolveUri(target)
        : Uri.parse(_origin + (path.startsWith('/') ? path : '/$path'));
    return ApiResourceAccess(
      url: resolved.toString(),
      headers: _isSameOrigin(originUri, resolved)
          ? authorizationHeaders
          : const {},
    );
  }

  /// 返回目标地址可使用的认证头；目标还必须位于当前服务的路径前缀内。
  Map<String, String> authorizationHeadersFor(String url) {
    final originUri = Uri.tryParse(_origin);
    final target = Uri.tryParse(url);
    if (originUri == null || target == null || !target.isAbsolute) {
      return const {};
    }
    return _isSameOrigin(originUri, target) ? authorizationHeaders : const {};
  }

  /// 原子替换活动服务和 token，并推进 epoch 使旧请求响应失效。
  void update({required String origin, String? token}) {
    _origin = _normalizeOrigin(origin);
    _token = token;
    _epoch++;
  }

  /// 立即清除本地会话，并推进 epoch 使所有在途请求失效。
  void clear() {
    _origin = '';
    _token = null;
    _epoch++;
  }

  static String _normalizeOrigin(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  static bool _isSameOrigin(Uri origin, Uri target) {
    if (!const {'http', 'https'}.contains(target.scheme.toLowerCase())) {
      return false;
    }
    return origin.scheme.toLowerCase() == target.scheme.toLowerCase() &&
        origin.host.toLowerCase() == target.host.toLowerCase() &&
        _effectivePort(origin) == _effectivePort(target) &&
        _hasPathPrefix(origin, target);
  }

  static bool _hasPathPrefix(Uri origin, Uri target) {
    final prefix = origin.normalizePath().path;
    final path = target.normalizePath().path;
    if (prefix.isEmpty || prefix == '/') return true;
    return path == prefix || path.startsWith('$prefix/');
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }
}

/// ApiResourceAccess 将解析后的资源地址和安全认证头作为不可分割的结果返回。
final class ApiResourceAccess {
  /// 创建已经完成同源认证判断的资源访问参数。
  const ApiResourceAccess({required this.url, required this.headers});

  /// 最终资源地址。
  final String url;

  /// 仅同源地址可能包含的认证头。
  final Map<String, String> headers;
}
