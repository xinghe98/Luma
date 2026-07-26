import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'api_session.dart';

final class ApiSessionInterceptor extends Interceptor {
  ApiSessionInterceptor(this.session);

  final ApiSession session;

  /// 绑定请求发起时的 origin、同源认证头和 epoch。
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.baseUrl = session.origin;
    options.extra[_sessionEpochKey] = session.epoch;
    options.headers.remove('Authorization');
    options.headers.addAll(
      session.authorizationHeadersFor(options.uri.toString()),
    );
    handler.next(options);
  }

  /// 只放行仍属于当前 epoch 的响应，避免旧会话结果进入仓储。
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!_isCurrent(response.requestOptions)) {
      handler.reject(_sessionChanged(response.requestOptions, response));
      return;
    }
    handler.next(response);
  }

  /// 将网络错误标准化；会话已切换时优先返回 SESSION_CHANGED。
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!_isCurrent(err.requestOptions)) {
      handler.next(_sessionChanged(err.requestOptions, err.response));
      return;
    }
    handler.next(err.copyWith(error: ApiException.fromDio(err)));
  }

  bool _isCurrent(RequestOptions options) =>
      options.extra[_sessionEpochKey] == session.epoch;

  DioException _sessionChanged(
    RequestOptions options,
    Response<dynamic>? response,
  ) => DioException(
    requestOptions: options,
    response: response,
    type: DioExceptionType.cancel,
    error: const ApiException(
      message: '会话已切换，忽略旧请求响应',
      code: 'SESSION_CHANGED',
    ),
  );

  static const _sessionEpochKey = 'luma.session_epoch';
}
