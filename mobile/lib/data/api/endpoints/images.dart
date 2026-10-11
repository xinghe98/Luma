// 图片上传端点复用当前 Dio 会话，逐张发送文件流并转发进度与取消。
part of '../api_client.dart';

/// POST /sources/{id}/images：multipart/form-data 单字段 file。
/// 逐张流式上传，进度与取消经 Dio 原生回调；服务端按 magic bytes 校验。
mixin _ImageUploadEndpoints on _ApiTransport {
  /// 上传一张图片；[filename] 必须是不含路径分隔符的 basename。
  /// 成功返回 201 JSON 原始 Map（media_id/filename），由调用方解码。
  Future<Map<String, dynamic>> uploadImage({
    required String sourceId,
    required String filename,
    required Stream<List<int>> stream,
    required int contentLength,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromStream(
        () => stream,
        contentLength,
        filename: filename,
        contentType: DioMediaType('image', _subtypeFor(filename)),
      ),
    });
    try {
      final response = await _dio.post<Object?>(
        _api('/sources/${_segment(sourceId)}/images'),
        data: form,
        cancelToken: cancelToken,
        onSendProgress: onProgress,
        options: Options(
          extra: {
            if (_session != null)
              ApiSessionInterceptor.expectedEpochKey: _session!.epoch,
          },
          responseType: ResponseType.json,
          // 上传时间随图片大小变化，不走全局 sendTimeout。
          sendTimeout: Duration.zero,
          receiveTimeout: const Duration(seconds: 30),
        ),
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

  /// 按扩展名推 Content-Type 子类型；服务端以字节内容为准，仅为网关友好。
  static String _subtypeFor(String filename) {
    final dot = filename.lastIndexOf('.');
    final ext = dot >= 0 ? filename.substring(dot + 1).toLowerCase() : '';
    return switch (ext) {
      'png' => 'png',
      'gif' => 'gif',
      'webp' => 'webp',
      'bmp' => 'bmp',
      _ => 'jpeg',
    };
  }
}
