// 图片上传仓储契约；由 ApiImageUploadRepository 实现，
// 经 ApiClient/Dio 走既有会话与代理管道，不持有队列状态。
import 'package:dio/dio.dart';

import '../models/image_upload_result.dart';

/// 把一张本地图片流式 POST 到指定媒体源。
/// 实现方负责 multipart 编码与 64 MiB 上限提示；调用方按来源逐张调用，
/// 通过 [onProgress] 回报已发送字节数（可能不精确到尽头），
/// 传入 [cancelToken] 取消在途请求。
abstract interface class ImageUploadRepository {
  /// 上传 [stream] 中的图片字节；[filename] 只含 basename（服务端拒收路径分隔符）。
  /// 会话切换或取消时抛 [DioException]/[ApiException]，已成功的写入由服务端保留。
  Future<ImageUploadResult> upload({
    required String sourceId,
    required String filename,
    required Stream<List<int>> stream,
    required int contentLength,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  });
}
