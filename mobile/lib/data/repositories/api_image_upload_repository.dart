// 图片上传仓储实现：经 ApiClient 走既有 Dio/会话/代理管道，
// 每次调用捕获会话 epoch，请求结束后校验，避免旧会话结果写入。
import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../models/image_upload_result.dart';
import 'image_upload_repository.dart';

final class ApiImageUploadRepository implements ImageUploadRepository {
  const ApiImageUploadRepository(this._client);

  final ApiClient _client;

  /// 流式上传一张图片到 [sourceId] 根目录。
  /// 会话在请求期间切换时抛 SESSION_CHANGED，已发送部分由服务端决定是否保留。
  @override
  Future<ImageUploadResult> upload({
    required String sourceId,
    required String filename,
    required Stream<List<int>> stream,
    required int contentLength,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    final epoch = _client.captureSessionEpoch();
    final json = await _client.uploadImage(
      sourceId: sourceId,
      filename: filename,
      stream: stream,
      contentLength: contentLength,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
    _client.ensureSessionEpoch(epoch);
    return ImageUploadResult.fromJson(json);
  }
}
