import 'package:flutter/material.dart';

/// 主题偏好持久化；读写失败不阻塞启动或切换。
abstract interface class ThemePreferenceStore {
  /// 读取保存的主题模式；从未写入或读取失败时返回 null。
  Future<ThemeMode?> read();

  /// 持久化主题模式选择。
  Future<void> write(ThemeMode mode);
}
