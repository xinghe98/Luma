import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'api_session.dart';
import 'api_session_interceptor.dart';

part 'endpoints/access.dart';
part 'endpoints/auth.dart';
part 'endpoints/catalog.dart';
part 'endpoints/media.dart';
part 'endpoints/system_sources.dart';
part 'endpoints/user_data.dart';

final class ApiClient extends _ApiTransport
    with
        _SystemSourceEndpoints,
        _MediaEndpoints,
        _CatalogEndpoints,
        _AccessEndpoints,
        _AuthEndpoints,
        _UserDataEndpoints {
  ApiClient(super._dio, {super.apiPrefix = defaultApiPrefix});

  static const defaultApiPrefix = '/api/v1';

  ApiClient isolatedFor(ApiSession session) {
    final dio = Dio(_dio.options.copyWith(baseUrl: ''))
      ..interceptors.add(ApiSessionInterceptor(session));
    return ApiClient(dio, apiPrefix: _apiPrefix);
  }

  /// 捕获当前会话 epoch，供包含多次 await 的仓储操作建立一致性边界。
  int captureSessionEpoch() => _session?.epoch ?? 0;

  /// 校验仓储操作仍属于捕获的会话；切换后抛错，禁止旧结果写入缓存。
  void ensureSessionEpoch(int epoch) {
    if (_session != null && _session!.epoch != epoch) {
      throw const ApiException(
        message: '会话已切换，忽略旧请求结果',
        code: 'SESSION_CHANGED',
      );
    }
  }

  void close() => _dio.close(force: true);
}

abstract class _ApiTransport {
  _ApiTransport(this._dio, {required String apiPrefix})
    : _apiPrefix = _normalizePrefix(apiPrefix);

  final Dio _dio;
  final String _apiPrefix;

  ApiSession? get _session {
    for (final interceptor in _dio.interceptors.reversed) {
      if (interceptor is ApiSessionInterceptor) return interceptor.session;
    }
    return null;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, responseType: ResponseType.json),
      );
      final body = response.data;
      if (body is Map<String, dynamic>) return body;
      if (body is Map) return Map<String, dynamic>.from(body);
      throw const ApiException(message: 'Expected a JSON object response');
    } on DioException catch (error) {
      throw error.error is ApiException
          ? error.error! as ApiException
          : ApiException.fromDio(error);
    }
  }

  Future<Response<List<int>>> _bytes(
    String path, {
    Map<String, dynamic>? headers,
  }) async {
    try {
      return await _dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          validateStatus: _acceptSuccessOrNotModified,
        ),
      );
    } on DioException catch (error) {
      throw error.error is ApiException
          ? error.error! as ApiException
          : ApiException.fromDio(error);
    }
  }

  Future<Response<void>> _empty(
    String method,
    String path, {
    Map<String, dynamic>? headers,
    Object? data,
  }) async {
    try {
      return await _dio.request<void>(
        path,
        data: data,
        options: Options(
          method: method,
          headers: headers,
          validateStatus: _acceptSuccessOrNotModified,
        ),
      );
    } on DioException catch (error) {
      throw error.error is ApiException
          ? error.error! as ApiException
          : ApiException.fromDio(error);
    }
  }

  String _segment(String value) => Uri.encodeComponent(value);

  String _api(String path) => '$_apiPrefix$path';

  static String _normalizePrefix(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '/') return '';
    final withLeadingSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return withLeadingSlash.replaceFirst(RegExp(r'/+$'), '');
  }

  static bool _acceptSuccessOrNotModified(int? status) =>
      status != null && status >= 200 && status < 400;
}
