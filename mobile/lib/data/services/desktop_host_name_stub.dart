// 非 IO 平台实现避免 Web 构建依赖 dart:io，并让调用方走平台名称兜底。

/// localDesktopHostName 在不支持读取主机名的平台返回空字符串。
String localDesktopHostName() => '';
