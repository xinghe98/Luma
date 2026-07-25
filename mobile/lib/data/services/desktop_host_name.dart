// 桌面主机名入口按运行平台选择实现，供登录设备命名组件读取本机名称。
export 'desktop_host_name_stub.dart'
    if (dart.library.io) 'desktop_host_name_io.dart';
