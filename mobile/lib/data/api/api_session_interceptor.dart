// Applies the active session to every request made by the application Dio.
import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'api_session.dart';

final class ApiSessionInterceptor extends Interceptor {
  ApiSessionInterceptor(this.session);

  final ApiSession session;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.baseUrl = session.origin;
    final token = session.token;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    } else {
      options.headers.remove('Authorization');
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(err.copyWith(error: ApiException.fromDio(err)));
  }
}
