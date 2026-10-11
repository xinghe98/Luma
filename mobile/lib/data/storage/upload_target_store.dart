// 上传目标记忆按服务器地址和已认证用户 ID 隔离，由控制器在成功上传后更新。
/// 读取或写入失败由上传控制器处理，不影响已经保存的图片。
abstract interface class UploadTargetStore {
  /// 返回该身份上次成功写入的来源 id；无记录或读取失败时返回 null。
  Future<String?> read(String identityKey);

  /// 持久化该身份的上传目标；覆盖同 key 旧值。
  Future<void> write(String identityKey, String sourceId);

  /// 清除已删除或被撤权的目标；普通断开连接保留记忆。
  Future<void> clear(String identityKey);
}
