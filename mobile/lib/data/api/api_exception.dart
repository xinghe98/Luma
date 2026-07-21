// Normalizes Dio and backend error envelopes for repositories and services.
import 'package:dio/dio.dart';

final class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.code,
    this.statusCode,
    this.details,
  });

  factory ApiException.fromDio(DioException error) {
    final data = error.response?.data;
    final errorBody = data is Map ? data['error'] : null;
    final body = errorBody is Map ? errorBody : null;
    return ApiException(
      message: body?['message'] as String? ?? error.message ?? 'Request failed',
      code: body?['code'] as String?,
      statusCode: error.response?.statusCode,
      details: body?['details'],
    );
  }

  final String message;
  final String? code;
  final int? statusCode;
  final Object? details;

  @override
  String toString() {
    final label = code == null ? 'ApiException' : 'ApiException($code)';
    return '$label: $message';
  }
}
