// 单张图片上传成功响应模型；由 ApiImageUploadRepository 解码，
// 仅承载服务端回执，不保留本地文件信息。
/// 单张图片上传成功后的服务端回执。
/// [filename] 是服务端实际落盘的名字，同名冲突时会带序号后缀，
/// 展示与日志都以它为准，不回推本地原名。
final class ImageUploadResult {
  const ImageUploadResult({required this.mediaId, required this.filename});

  final String mediaId;
  final String filename;

  static ImageUploadResult fromJson(Map<String, dynamic> json) {
    final mediaId = json['media_id'];
    final filename = json['filename'];
    if (mediaId is! String || mediaId.isEmpty) {
      throw const FormatException('上传响应缺少 media_id');
    }
    if (filename is! String || filename.isEmpty) {
      throw const FormatException('上传响应缺少 filename');
    }
    return ImageUploadResult(mediaId: mediaId, filename: filename);
  }
}
