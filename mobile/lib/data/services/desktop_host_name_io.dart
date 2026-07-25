// IO 平台实现读取操作系统提供的本机主机名，不保存或上传额外设备标识。
import 'dart:io';

/// localDesktopHostName 返回当前桌面系统的主机名，读取失败时返回空字符串。
String localDesktopHostName() => Platform.localHostname;
