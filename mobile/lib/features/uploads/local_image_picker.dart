// 原生图片选择适配器为上传控制器提供文件信息和可重开的读取流；不在选图时加载完整图片到内存。

import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// 服务端接受的图片扩展名集合（与扫描器一致）。
const kUploadImageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
};

/// 单张待上传本地图片；只持路径与元信息，字节经 [openRead] 流式提供。
final class LocalImage {
  /// 保存本地文件引用；调用方在上传或预览需要时才读取内容。
  const LocalImage({
    required this.path,
    required this.filename,
    required this.contentLength,
    required this.openRead,
  });

  /// 本地路径，仅用于缩略图与去重；上传时不发送路径。
  final String path;

  /// 不含目录的原始文件名，作为 multipart filename 属性。
  final String filename;

  /// 文件字节数；控制器会提示空文件和超过上传上限的项目。
  final int contentLength;

  /// 打开读取流；每次调用返回新的流，由调用方负责消费或取消。
  final Stream<List<int>> Function() openRead;
}

/// 拉起系统多选图片对话框的抽象；返回 null 表示用户取消。
/// 超限项仍返回，由 controller 标记 RejectedImage 给用户提示。
abstract interface class LocalImagePicker {
  /// 打开原生选择器；用户取消返回 null。
  Future<List<LocalImage>?> pick();
}

/// 单文件上传上限：服务端硬性 64 MiB。
const kUploadMaxBytes = 64 * 1024 * 1024;

/// Android 与 Windows 共用的系统多选器；Android 返回缓存副本的本地路径。
final class NativeLocalImagePicker implements LocalImagePicker {
  /// 构建无状态选择器，不请求全盘读取权限。
  const NativeLocalImagePicker();

  /// 多选支持的图片；取消返回 null，系统读取失败交给控制器提示。
  @override
  Future<List<LocalImage>?> pick() async {
    final selected = await FilePicker.pickFiles(
      dialogTitle: '选择上传图片',
      type: FileType.custom,
      allowedExtensions: kUploadImageExtensions.toList(growable: false),
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
    if (selected == null || selected.files.isEmpty) return null;
    return [for (final file in selected.files) _localImage(file)];
  }

  LocalImage _localImage(PlatformFile selected) {
    final path = selected.path;
    if (path == null || path.isEmpty) {
      throw FileSystemException('无法读取所选图片：${selected.name}');
    }
    final file = File(path);
    return LocalImage(
      path: path,
      filename: selected.name,
      contentLength: selected.size,
      openRead: file.openRead,
    );
  }
}
