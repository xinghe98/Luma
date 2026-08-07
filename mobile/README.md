# 轻影 Luma · Flutter 客户端

轻影是一款连接家庭服务器或内网服务器的私有视频、图片管理播放器。本目录提供 Android 与 Windows 10/11 x64 客户端，并适配手机、平板和桌面宽屏。媒体浏览、搜索、详情、缩略图、原图、播放、用户数据和扫描状态均来自 Luma 服务端 API。

## 运行

环境：Flutter 3.41.6（stable）及 Dart 3.11.4。

```bash
flutter pub get
flutter run
```

连接时填写服务端地址、端口、用户名和密码；登录成功后客户端保存服务端签发的独立设备会话。会话默认有效 30 天，也可由服务端配置提前到期或撤销；远程连接应使用 HTTPS。业务 API 默认使用 `/api/v1`，可通过 `--dart-define=LUMA_API_PREFIX=/api/v2` 覆盖。

静态检查与测试：

```bash
dart format .
flutter analyze
flutter test
```

Android 调试包可通过 `flutter build apk --debug` 构建。

Windows 使用标准标题栏，默认窗口为 1280×800，最小尺寸为 960×640。Release NSIS 安装包一键构建：

```powershell
.\package-windows.ps1
```

脚本会调用 `backend/scripts/windows-deploy.ps1 -Action PackageClient`，构建 Windows Release 并输出 `build/dist/luma-windows-x64-<version>-setup.exe`。需本机已安装 Flutter、Visual Studio C++ 工具链与 NSIS 3（`makensis`）。当前不提供 MSIX、自动更新、ARM64 或代码签名。

## VMess 内网代理

连接页右上角「代理」可启用内嵌 VMess 代理：

1. 点右上角蓝色「代理」。
2. 在弹层中粘贴或填写一条 `vmess://` 分享链接，选择「连接」。
3. 按钮变为「代理已开」后，再填写内网 Luma 服务器地址和账号。

- 仅支持 Android 与 Windows x64，只接受单条 VMess 分享链接，不接受订阅、多节点文本、VLESS、Trojan 或 Shadowsocks。
- 分享链接保存在系统安全存储。每次 App 进程启动后都保持“未启动”，必须由用户手动开启。
- 启动后，Dio API、Flutter 图片和 `media_kit` 视频请求都经过应用内代理。视频由仅监听 `127.0.0.1` 的 Range relay 流式转发。
- 代理只作用于轻影，不创建系统 VPN/TUN，不申请 VPN 权限，也不修改系统代理或其他应用的流量。
- 断开服务器会话不会关闭代理。代理保持运行，直到用户在连接页手动关闭或 App 进程退出。
- 内嵌核心固定为 [libXray v26.7.28](https://github.com/XTLS/libXray/tree/v26.7.28)，其包含 [Xray-core v26.7.28](https://github.com/XTLS/Xray-core/tree/v26.7.28)。libXray 使用 MIT 许可，Xray-core 使用 MPL-2.0，完整文本随应用分发并可从“关于轻影 → 开源许可”查看。

已入库的 AAR、DLL 和许可文本可重复同步，不在 Gradle 或 CMake 构建期间联网：

```powershell
.\tool\sync_libxray.ps1
```

## 服务器连接

- `/health` 用于检测服务存活。
- `/api/v1/system/info` 用于验证当前会话，并读取版本、平台、架构和数据库状态。
- 地址和会话凭据使用系统安全存储；设置页断开连接时清除连接凭据。
- 服务器别名仅保存在当前客户端，可在设置页编辑，不写入服务端。
- 管理员账号会显示扫描、媒体源类型和“成员与访问管理”入口；成员账号根据 `/system/info` 的 capabilities 自动隐藏这些管理操作。
- “成员与访问管理”可创建或启停成员、设置成员密码、授予媒体源访问权，并查看或撤销其已登录设备。
- 登录设备会优先显示手机的本地营销型号；Windows、macOS 和 Linux 桌面端显示主机名。读取失败时回退为平台名称。
- 管理员也可使用后端的 `luma-admin` 命令行工具进行批量管理；该工具每次执行都会以管理员账号登录并使用设备会话。

连接成功后会进入主应用；设置页可以断开并回到首次连接页。收藏、笔记和播放进度写入服务端，缩略图缓存由 Flutter 图片缓存管理。

## 页面结构

- 首次连接：VMess 代理导入与启停、地址输入、最近服务器，以及加载、成功和失败反馈。
- 首页：欢迎区、扫描状态、继续观看、最近添加和收藏。
- 图片库：图片瀑布流、收藏、排序、下拉刷新和响应式布局。
- 影视库：电影、电视剧、个人视频三个常驻分页；电影和电视剧使用 2:3 竖版海报墙，个人视频保留原文件卡片体验且不会混入影视来源。
- 搜索：最近搜索、类型/标签组合筛选和无结果状态。
- 媒体详情：封面、播放/大图、收藏、元数据、标签、笔记、媒体源名称和文件名。
- 播放器：使用 `media_kit`/libmpv 播放认证视频流和 HTTP Range；代理活动时由应用内 loopback relay 转发，移动端支持手势与锁定，Windows 支持音量、全屏、鼠标和键盘控制。
- 设置：服务器状态、扫描、媒体源类型、缓存、关于和断开连接；主题切换在页面右上角。

手机使用 Material 3 底部导航（首页、图片库、影视库、搜索、设置）；宽度达到 840px 后切换为侧边导航。Windows 窗口最小宽度为 960px，因此始终使用侧边导航，并为媒体卡片、横向货架、筛选和图片预览提供键鼠交互。媒体网格会在 2–5 列间自适应，详情页在宽屏使用双栏布局。默认浅色主题，可在设置页右上角切换深色。

Windows 常用快捷键：`Ctrl+F` 搜索、`Alt+Left` 返回；播放器使用 `Space`/`K` 播放暂停、方向键快进快退与调节音量、`M` 静音、`F` 全屏、`Esc` 退出全屏或关闭播放器。

Windows 与 Android 共用现有 OpenAPI、认证、Range 流式传输和进度同步接口。桌面端的广泛格式兼容由随客户端发布的 libmpv 提供，后端无需恢复实时转码链路。

电影/电视剧作品详情中的主播放按钮和选集会直接进入播放器；个人视频仍先进入媒体详情。海报优先使用作品目录内的 `poster.*`、`folder.*`、`cover.*`（JPG/JPEG/PNG/WebP），没有本地海报时由代表视频缩略图以竖版 cover 方式展示。列表图片按卡片实际设备像素解码，分页之间保留状态并限制预构建范围，以降低快速滚动时的纹理和重建峰值。

## 代码结构与后端接入

- `lib/app/`：依赖组装、Scope，以及会话、媒体和设置共享 Controller。
- `lib/data/api/`：Dio 请求、API Prefix、会话认证和统一错误。
- `lib/data/proxy/`：VMess 配置安全存储、libXray 原生桥、动态 HTTP 路由和媒体 Range relay。
- `lib/data/decoders/`：独立的 JSON 到类型模型映射。
- `lib/data/repositories/`：媒体、来源和扫描数据边界。
- `lib/data/mock/`、`lib/data/fixtures/`：仅供测试使用，不进入生产依赖图。
- `lib/features/`：每个页面独立目录，包含页面入口、Controller、widgets 和 dialogs。
- `lib/shared/`：按 branding、media、states、layout、formatters 分类的跨页面组件。
- `assets/`：轻影品牌 Logo 与 Android App 图标源文件。

页面入口只负责响应式布局和组件编排；异步状态、筛选和业务动作由对应 Controller 管理。页面不直接依赖 Dio 或解析 JSON，项目继续使用 `ChangeNotifier`、构造注入和 `AppScope`，不引入全局 Service Locator。

代码质量约定：页面入口目标低于 120 行，普通 Dart 文件目标不超过 200 行；提交前运行格式化、静态检查和测试。
