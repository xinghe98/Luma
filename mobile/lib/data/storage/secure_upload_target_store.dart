// 按已认证账号和服务器分别保存上传目标，复用安全存储；各身份独立读写，避免整表覆盖。

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'upload_target_store.dart';

/// 上传目标记忆；存储错误由上传控制器处理，不影响已保存的图片。
final class SecureUploadTargetStore implements UploadTargetStore {
  /// 复用应用安全存储，每个身份只保存一个媒体源 ID。
  const SecureUploadTargetStore(this._storage);

  final FlutterSecureStorage _storage;

  /// 读取上次成功目标；未保存时返回 null。
  @override
  Future<String?> read(String identityKey) =>
      _storage.read(key: _key(identityKey));

  /// 更新当前身份的目标，不读取或覆盖其他账号的记录。
  @override
  Future<void> write(String identityKey, String sourceId) =>
      _storage.write(key: _key(identityKey), value: sourceId);

  /// 删除失效目标，让下次上传重新选择。
  @override
  Future<void> clear(String identityKey) =>
      _storage.delete(key: _key(identityKey));

  static String _key(String identityKey) =>
      'luma.upload.target.${Uri.encodeComponent(identityKey)}';
}
