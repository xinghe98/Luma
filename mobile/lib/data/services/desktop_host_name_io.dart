// IO 平台实现读取主机名与系统登录用户名，供登录设备命名使用。
import 'dart:io';

/// localDesktopHostName 返回当前桌面系统的主机名，读取失败时返回空字符串。
String localDesktopHostName() {
  try {
    return Platform.localHostname.trim();
  } on Object {
    return '';
  }
}

/// localDesktopUserName 返回操作系统登录用户名，过滤空值与 Windows 系统账户。
String localDesktopUserName() {
  try {
    final env = Platform.environment;
    final raw = (env['USER'] ?? env['USERNAME'] ?? '').trim();
    if (raw.isEmpty) return '';
    switch (raw.toLowerCase()) {
      case 'system':
      case 'local service':
      case 'network service':
        return '';
      default:
        return raw;
    }
  } on Object {
    return '';
  }
}
