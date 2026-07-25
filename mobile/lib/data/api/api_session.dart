final class ApiSession {
  ApiSession({String origin = '', String? token})
    : _origin = _normalizeOrigin(origin),
      _token = token;

  String _origin;
  String? _token;

  String get origin => _origin;
  String? get token => _token;
  Map<String, String> get authorizationHeaders =>
      _token == null ? const {} : {'Authorization': 'Bearer $_token'};

  /// 将服务端相对资源路径拼到当前 origin，且保留反向代理前缀。
  /// 后端返回的资源路径以 `/api/...` 开头。`Uri.resolve` 会把它当作
  /// host 根路径，从而丢掉诸如 `https://host/luma` 中的 `/luma` 前缀。
  String resolve(String path) {
    final target = Uri.tryParse(path);
    if (target != null && target.hasScheme) return path;
    if (_origin.isEmpty) return path;
    return _origin + (path.startsWith('/') ? path : '/$path');
  }

  void update({required String origin, String? token}) {
    _origin = _normalizeOrigin(origin);
    _token = token;
  }

  void clear() {
    _origin = '';
    _token = null;
  }

  static String _normalizeOrigin(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }
}
