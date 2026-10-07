# 轻影 Luma · Flutter 客户端

轻影是一款连接家庭服务器或内网服务器的私有视频、图片管理播放器。本目录提供 Android 与 Windows 10/11 x64 客户端，并适配手机、平板、桌面宽屏与 Android TV。媒体浏览、搜索、详情、缩略图、原图、播放、用户数据和扫描状态均来自 Luma 服务端 API。

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

Windows 使用标准标题栏，默认窗口为 1280×800，最小尺寸为 960×640。

## Release 打包

`script/package.ps1` 是唯一客户端打包入口。在 `mobile` 目录运行，无参默认构建全部平台，`-p` 只选择一个平台；所有构建均为 release：

```powershell
./script/package.ps1
./script/package.ps1 -p tv
./script/package.ps1 -p android
./script/package.ps1 -p win
```

默认全平台打包需要 Windows 主机、Windows PowerShell 5.1 或 PowerShell 7、Flutter、Android SDK、JDK 17、Visual Studio C++ 工具链与 NSIS 3（`makensis`）。系统自带 PowerShell 可以直接执行上述命令；`-p` 必须放在脚本路径之后，例如 `powershell.exe -NoProfile -File .\script\package.ps1 -p win`。Visual Studio C++ 和 NSIS 仅用于 `win`；只构建 TV 或 Android 时不需要。Linux 安装 PowerShell 7 后可运行：

```bash
pwsh -File ./script/package.ps1 -p tv
pwsh -File ./script/package.ps1 -p android
```

版本统一读取 `app_metadata.json`，打包前执行 `dart run tool/sync_app_metadata.dart --check`，不自动改写元数据。若生成结果过期，先手动执行 `dart run tool/sync_app_metadata.dart` 同步，再重新打包。

产物固定归集到项目的 `mobile/build/dist/`，与执行命令时所在目录无关；文件名采用「应用名-版本-平台-架构」格式：

| 参数 | 架构与形态 | 产物 |
| --- | --- | --- |
| `-p tv` | 一个强制 TV APK，包含 `armeabi-v7a` + `arm64-v8a` | `luma-<version>-android-tv-armv7-arm64.apk` |
| `-p android` | 手机 APK，仅 `arm64-v8a` | `luma-<version>-android-arm64-v8a.apk` |
| `-p win` | Windows 10/11 x64 NSIS 安装包 | `luma-<version>-windows-x64-setup.exe` |

APK 沿用 `android/key.properties` 的 release 签名配置；没有签名配置时不回退 debug 签名，文件名增加 `-unsigned.apk` 后缀，保持未签名、不可发布状态。Gradle 只负责构建，`build/dist/` 的归集由统一入口完成。Windows 当前不提供 MSIX、自动更新、ARM64 或代码签名。

全平台按 TV、Android、Windows 顺序构建，任一平台失败即停止。APK 归集前会检查准确 ABI 集合和各架构的 Flutter/AOT、libmpv、libXray 库；Windows 安装包组装前会检查关键 DLL、资源和许可。输出目录保留其他平台与历史版本的产物，成功生成后才替换本次同名发行文件。

## Android TV

电视端定位为「专注观看」：首页、图片库、影视库、搜索、详情、播放和图片预览全部可用；扫描、媒体源、成员与访问管理保留在手机/Windows 端操作。TV 的设置页隐藏这些管理入口（只读状态仍可见），深链 `/settings/sources`、`/settings/access`、`/settings/access/new`、`/settings/access/:userId` 一律回到设置页，连接成功后也不再自动恢复扫描轮询。笔记编辑入口在 TV 隐藏，收藏通过详情页的可见按钮操作。TV 默认使用深色主题，仍可在设置页切换。

### 电视端布局

- 左侧导航在内容浏览时收为图标栏，返回导航时展开名称；展开覆盖内容，不挤动海报和货架。导航项在栏内垂直居中。首页首屏是继续观看的横幅：画面贴右、标题和播放贴左，下方再按横向货架浏览。
- 影视库宽屏把标题、电影/电视剧/个人视频和搜索、刷新放在同一行；窄屏改为上下重排。海报货架和完整分类都用 2:3 封面，焦点只框封面。
- 作品详情把画面铺进首屏，标题和播放叠在左侧，简介和选集另起一区。个人媒体详情同样用横幅，并保留完整文件名与元数据。播放器仍是顶部标题、底部时间轴和集中操作区。
- 图片预览的详情和关闭落在画面底部，并带文字。设置行获焦时整行填色。连接页在宽视口将品牌说明与登录字段分栏，字段宽度不超过 520dp。窄视口仍能重排，手机和 Windows 继续使用各自现有页面分支。
- TV 使用独立文字层级、56dp 操作目标和 3dp 焦点描边，保留浅色/深色主题及系统文字缩放。展示组件共用原有 Controller、Repository、路由数据和播放链路，没有新增服务端协议。


### 设备识别与安装

- 普通包在 Android 上自动读取系统特征：包含 `android.software.leanback` 或 `android.hardware.type.television` 即进入 TV 界面；不按屏幕宽度、外接键盘或鼠标判断。其他平台始终为普通界面。
- 部分盒子 ROM 不报告 TV 特征，需改用强制 TV 包（带 `--dart-define=LUMA_TV=true` 构建，见下）。TV 包与普通包同包名、同签名，覆盖安装即切换形态；手机安装 TV 包也会进入 TV 界面，分发时须明确标识专用 TV 包。
- 系统要求 Android 7.0（API 24）及以上，与现有 Flutter 工具链一致。

### 遥控器操作

- D-pad 移动焦点，OK/确认键激活；确认键长按重复不会重复触发，方向键支持长按连移。媒体卡片的 3dp 描边只围住封面，不框整张卡片。页面背景覆盖整个可用区域，内容四边安全留白最多 24dp，避免大屏按百分比形成过宽边框；正文仍受既有最大宽度约束，播放器控制层独立保留过扫描安全区。
- Back、Escape 与遥控返回键使用同一层级：收起输入法 → 关闭弹层/对话框 → 退出详情、集合或图片预览 → 焦点回到左侧导航 → 非首页导航回首页 → 再次返回退出到系统桌面。无退出确认，无导航循环。
- 播放器：控制层隐藏时 OK 切换播放/暂停、左右键 ±10 秒快进快退、上下键呼出控制层；控制层显示时方向键在按钮与进度条间移动。媒体键支持播放/暂停、快进、快退；系统音量、静音和 Home 键交给系统处理。播放速度在控制层对话框中选择。TV 不提供小窗、锁定、旋转、亮度与软件音量控制。
- 深链 `luma://app/...` 在 TV 上同样可用；无来源栈的播放器退出后回首页。
- 从导航首次向右进入页面会落到可操作控件；内容左边界可向左回导航，再次进入恢复该分支焦点。列表重排按媒体 ID 保持焦点，删除当前项时落到相邻有效项，不抢走正在编辑或弹窗中的焦点。
- 电影、电视剧与个人视频的“查看全部”在新路由内主动交付可操作首焦点，方向键可移动和滚动，确认键打开详情。按钮、系统 Back 与 Escape 从详情返回实际来源页并保留卡片焦点和滚动位置；只有无来源深链的详情回首页，独立分类列表回影视库。焦点隔离仅跟随导航分支切换，不因详情遮盖来源页而清除历史。
- 图片库和个人视频工具栏提供遥控刷新。首页加载、收藏与进度更新即时反映在货架上；刷新失败保留已有内容。搜索提交后先滚动展示首条结果再移交焦点，离开页面或修改查询后取消旧提交的交接。
- 详情主操作获焦时滚入可见范围；长简介只在自身范围内翻页，到末尾后交给选集。选集、卡片和对应骨架随字体缩放调整高度，封面比例不变。
- 字段的粘贴、清除等按钮可直接确认；焦点描边不会重建输入框。选择弹窗会展示当前选项，长按确认只处理首次按下；倍速弹窗打开期间播放器控制层保持可见。图片缩小后重新约束边缘，恢复原尺寸时居中。

### 构建与分发

TV release 使用统一入口，输出一个双 ARM APK：

```powershell
./script/package.ps1 -p tv
```

手机、TV 与模拟器的 debug 验证命令保持独立：

```bash
# 手机默认包：仅 arm64-v8a，行为与 TV 适配前一致
flutter build apk --debug

# TV 强制包（双 ARM debug）：覆盖 32 位与 64 位电视盒子
flutter build apk --debug --target-platform android-arm,android-arm64 \
  --dart-define=LUMA_TV=true --android-project-arg=lumaTvAbis=arm

# 模拟器隔离验证：仅 x86_64，不作为分发包
flutter build apk --debug --target-platform android-x64 \
  --dart-define=LUMA_TV=true --android-project-arg=lumaTvAbis=emulator
```

- `lumaTvAbis` 取值：缺省或 `arm64` 仅 `arm64-v8a`；`arm` 为 `armeabi-v7a` + `arm64-v8a`；`emulator` 仅 `x86_64`；其他值构建直接失败。统一入口对 `android` 显式传入 `arm64`，对 `tv` 传入 `arm`。ABI 过滤与 jniLibs 剔除由同一取值派生，不会互相矛盾。
- TV 与手机 release 产物分别归集到 `build/dist/`，文件名与签名规则见上方「Release 打包」；直接运行 Gradle/Flutter 构建不负责复制分发产物。
- 包内容预期：双 ARM 包的 `lib/armeabi-v7a/` 与 `lib/arm64-v8a/` 都应含 `libflutter.so`、`libgojni.so`、`libmpv.so`（release 另需 AOT 的 `libapp.so`），且不含 x86/x86_64；手机包应仅含 `lib/arm64-v8a/`。Manifest 可用 `apkanalyzer manifest print` 复核 LEANBACK_LAUNCHER 入口、非必需 leanback/touchscreen 特征、TV banner 与 `luma://` 深链。编译后的 banner 可能显示为 `@ref/0x...`，CI 从同一 APK 的资源表确认其对应 `drawable/tv_banner`。
- CI（`.github/workflows/mobile.yml`）：verify job 先构建手机 debug 包并断言仅含 arm64，tv-arm-debug job 在独立工作区构建双 ARM debug 包、断言双 ARM ABI 与 Manifest 声明后上传 `luma-tv-arm-debug` artifact；各 job 产物互不覆盖。
- 格式兼容范围由随客户端分发的 libmpv 与设备硬件解码能力决定，不做后端实时转码。

### 隔离原生冒烟

`integration_test/tv_smoke_test.dart` 使用内存仓储、独立会话和本机随机端口测试服务器，覆盖连接、浏览、搜索、详情、播放、返回、图片预览与设置。视频经真实鉴权、Range relay 和 libmpv 解码；不会读取已保存凭据或连接用户服务器。测试使用设备真实视口，不覆盖原生窗口指标。

Windows 上对已启动的 x86_64 模拟器运行：

```powershell
$tvSmokePreviousGradleOpts = $env:GRADLE_OPTS
try {
  $env:GRADLE_OPTS = "$tvSmokePreviousGradleOpts -Dorg.gradle.project.lumaTvAbis=emulator"
  flutter test integration_test/tv_smoke_test.dart -d emulator-5554 --dart-define=LUMA_TV=true --reporter expanded
} finally {
  $env:GRADLE_OPTS = $tvSmokePreviousGradleOpts
}
```

`flutter test` 不支持 `--android-project-arg`，因此通过 JVM 属性传递同一个 ABI 选择；构建依然需要兼容的 JDK。截图在平台支持时写入应用临时目录的 `luma_tv_smoke_screenshots`，最终测试报告包含路径和截图错误；截图失败不替代行为断言。

需留存截图时，在同一临时 `GRADLE_OPTS` 配置下改用 `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/tv_smoke_test.dart -d emulator-5554 --dart-define=LUMA_TV=true`；现有宿主驱动会把截图写入 `build/integration_screenshots/`，避免测试卸载应用后丢失设备内文件。

图片检查要求首页缩略图与预览完成真实解码；截图等待转场和重绘结束。Android 视频还必须在截图中央出现测试素材的红绿条纹，`videoPixelsVisible` 为 false 时整个 smoke 失败，即使播放进度和首帧回调正常。宿主驱动在失败时同样保留截图及 `build/integration_response_data.json`，用于区分业务断言与模拟器原生纹理问题。

2026-10-05 本机验证：API 33 Google APIs x86_64 镜像、`tv_1080p` 设备配置、1920×1080 / 320dpi、SwiftShader 下完整原生冒烟通过，包括三类“查看全部”的方向/确认操作、详情返回原列表与焦点恢复、搜索结果可见焦点、真实视频像素、鉴权/Range、进度保存和返回清理。页面边缘像素另由手机至 4K 尺寸的浅色/深色回归覆盖。API 36 在同一 Emulator 35.5.10 的 Radeon 宿主渲染与 SwiftShader 渲染下仍有视频黑屏，日志出现 `eglCreateContext: EGL_BAD_ATTRIBUTE`；该环境未通过画面验收。模拟器通过不能代替下述电视盒子真机验收。

2026-10-06 TV 重排后，隔离原生冒烟再次通过：遥控器完成分类浏览、搜索、详情、播放及图片预览返回，设置可切换浅色/深色主题。报告记录 3 次 Range 请求、0 次鉴权失败、4 次进度保存，`videoPixelsVisible=true`；14 张页面截图保存在 `build/integration_screenshots/`。全量 618 项测试及 `flutter analyze` 通过；Android debug、Windows release 与 NSIS 安装包构建通过。这里的截图使用测试媒体，仍需真实电视遥控器与硬件解码验收。

`integration_test/player_failure_smoke_test.dart` 专门覆盖真实 libmpv 的错误与恢复：隔离服务先返回 HTTP 401，现有播放器错误区域显示上游状态并隐去本机路由 token；更新内存测试会话后，通过「重试播放」重新取得 Range 视频并推进播放位置。运行方式同上，将测试文件名替换即可；Windows 可运行 `flutter test integration_test/player_failure_smoke_test.dart -d windows`。此用例不读取真实凭据，也不证明特定电视或生产 VMess 节点可用。

2026-10-07 修复 TV 播放期间的场景重建：播放位置和缓冲通知继续更新局部控件，只有控制层显隐或错误引起遥控按键模式变化时才重建 TV 场景。临时重建计数验证中，控制层隐藏后的 10 次进度更新，视频区域重建从 10 次降为 0 次；该计数不等于真机掉帧率。回归覆盖窄屏/宽屏、浅色/深色下的进度显示、触控暂停、遥控显隐与错误重试；Windows 隔离 libmpv 错误恢复冒烟通过。硬解策略、缓存参数和显示刷新率未调整，实际电视的解码丢帧与显示节奏仍需真机确认。

此次验证：`flutter analyze` 与全量 622 项测试通过；Android debug、双 ARM TV release、Windows release 和 NSIS 构建通过。TV release 的 v2 签名与两种 ARM 的 Flutter/AOT/libmpv/libXray 库均已校验；Windows 安装包包含运行库、data、使用说明与许可。TV 包位于 `build/dist/luma-tv-arm-1.2.1-release.apk`，本次未连接真实电视做流畅度验收。

同日真实 TCL Android TV（32 位系统）复查确认：GPU 直接 MediaCodec 初始化报 `Could not open codec.`，随后退回 `mediacodec-copy`。同一段 3840×1920、25fps、8-bit BT.709 SDR 的 HEVC 视频在本地隔离服务播放，兼容回拷 + GPU 路径约 20 秒后音画偏差达 4.02 秒、丢 203 帧；MediaCodec Surface 直出路径偏差接近 0、丢帧为 0，排除了此次复现中的后端和网络供给影响。

TV 现改为暂停预读真实视频格式与硬解结果，只有已确认的 8-bit BT.709 SDR 且 `hwdec-current=mediacodec-copy` 时才创建 `mediacodec_embed` Surface 输出。HDR、10-bit、旋转、未知格式或无硬解仍使用 GPU 兼容输出；Surface 解码或视频输出链失败时，每个播放会话最多重建一次兼容播放器，并保留进度、暂停意图、音量和倍速。继续共用 media_kit/libmpv、鉴权、Range 和进度协议，不改变片源或增加后端转码。

可恢复的原生错误只在视频链路有效、非定位且位置持续推进后清除；音频独走、快进跳跃、旧会话回调和后续命令失败不能清除当前错误。HTTP 206 仅作为传输上下文；空错误消息不会生成只有传输诊断的提示。视频链致命日志也会被捕获，避免 Surface 无法接收软件帧时只剩声音。真实打开失败与缓冲超时继续保留重试入口。

真机隔离验收已覆盖从 3 秒续播、暂停定位再播放、强制硬解失败后自动重建 GPU、软件帧显示、旧 GPU 路径成功回退后清除错误。三种路径截图为 `build/integration_screenshots/tcl-production.png`、`tcl-forced-fallback.png`、`tcl-legacy-recovery.png`，原生读数保存在 `build/tv_playback_verification.json`。软件回退只验证兼容性，不承诺该电视的软件解码能流畅处理 4K HEVC。`flutter analyze`、全量 640 项测试和 Windows 隔离原生 HTTP 401 / 重试冒烟通过；临时诊断包、素材与测试入口已移除。其他电视型号与 HDR 片源仍需独立真机验收。

本轮同时通过 Android debug、TV 双 ARM release、手机 ARM64 release、Windows release 与 NSIS 构建。TV APK 的 v2 签名、两种 ARM 的 Flutter/AOT/libmpv/libXray 库和正式应用 ID 已核对；Windows 安装包内的 plugin、libmpv、libXray、VC++ DLL、data、说明与许可齐全。三份发行包均已排除临时诊断素材，统一保存在 `build/dist/`。

### 验证边界

CI 的 ABI 与 Manifest 检查是 APK 静态结构检查，不等同于真机验收。发布前至少需要：一台 32 位 Android 系统盒子与一台 64 位 Android TV/Google TV，用真实遥控器覆盖 D-pad、OK、Back、Home、音量与媒体键，以及 H.264/AAC、HEVC、MKV、图片浏览、网络中断重试等场景；`adb shell input keyevent` 的方向/确认/返回/Home/媒体键码可辅助验证。签名密钥未配置时 release 包只能标记为未签名，不得当作发布就绪。

## VMess 内网代理

连接页右上角「代理」可启用内嵌 VMess 代理：

1. 点右上角蓝色「代理」。
2. 在弹层中粘贴或填写一条 `vmess://` 分享链接，选择「连接」。
3. 按钮变为「代理已开」后，再填写内网 Luma 服务器地址和账号。

- 仅支持 Android 与 Windows x64，只接受单条 VMess 分享链接，不接受订阅、多节点文本、VLESS、Trojan 或 Shadowsocks。
- 分享链接保存在系统安全存储。每次 App 进程启动后都保持“未启动”，必须由用户手动开启。
- 启动后，Dio API、Flutter 图片和 `media_kit` 视频请求都经过应用内代理。视频始终由仅监听 `127.0.0.1` 的 Range relay 转发，代理只改变 relay 的上游传输：关闭时直连服务端，开启时经 VMess 内嵌核心。
- 每次播放只解析一次入口地址：relay 首次跟随服务端的 302 入口后即固定最终地址（原始文件或 faststart 缓存副本），此后本次播放的所有 Range/If-Range 请求都直接访问该地址，不会在两种表示之间来回切换。只有重新开始播放（含用户显式重试）才会重新解析入口并可能改选缓存副本。relay 的每一跳上游请求都新建连接：内嵌 Xray 的 HTTP 入站回完一个响应就会断开，却仍声明 keep-alive，复用连接会让跟随 302 的请求发不出去。
- 播放失败与准备/缓冲超时时，错误提示附带本次路由最近发起请求的进度：尚未收到播放器请求、正在等待上游响应头、上游 HTTP 状态、已从上游读取的字节量，以及连接、TLS、响应头超时或重定向错误类别。字节量表示中继已读取的数据，不等于播放器已解码；并发旧请求的结果不会覆盖新请求，播放器主动取消与上游断流分别记录。
- 诊断只保存在当前播放的内存中，失败时附在既有错误区域；不会记录服务器地址、认证头、路由 token 或响应内容，重试创建新路由并清空旧诊断。初始化期间明确的 `Failed to open` 会结束该代初始化，避免后续完成回调清掉错误。遇到无法复现的电视故障，可记录屏幕上的完整错误与上游状态，不需要开放提示中的本机端口。
- 本次固定流表示修复需要同时更新服务端与客户端。旧服务端仍可能让同一地址切换文件布局，旧客户端则可能在 seek 时重新选择入口；只更新其中一侧无法保证整次播放的字节一致。
- 代理只作用于轻影，不创建系统 VPN/TUN，不申请 VPN 权限，也不修改系统代理或其他应用的流量。
- 断开服务器会话不会关闭代理。代理保持运行，直到用户在连接页手动关闭或 App 进程退出。
- 内嵌核心固定为 [libXray v26.7.28](https://github.com/XTLS/libXray/tree/v26.7.28)，其包含 [Xray-core v26.7.28](https://github.com/XTLS/Xray-core/tree/v26.7.28)。libXray 使用 MIT 许可，Xray-core 使用 MPL-2.0，完整文本随应用分发并可从“关于轻影 → 开源许可”查看。

`tool/sync_libxray.ps1` 是独立依赖维护工具，不是打包入口。已入库的 AAR、DLL 和许可文本可重复同步，不在 Gradle 或 CMake 构建期间联网：

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
- 播放器：使用 `media_kit`/libmpv 播放认证视频流和 HTTP Range；视频始终经应用内 loopback relay 转发（相对 Location、认证头和 Range 都由 relay 处理），移动端支持手势与锁定，Windows 支持音量、全屏、鼠标和键盘控制，TV 使用仅含播放/暂停、±10 秒定位、倍速与关闭的遥控控制层。快进、拖动提交、取消拖动回到起点和从头播放共用一条定位链路：等待 libmpv 完成定位期间显示缓冲提示（与原生缓冲状态叠加），期间过时的播放位置不会把滑块拉回，被新的定位、拖动、重试或关闭取代的请求不会再恢复播放或写入进度。
- 设置：服务器状态、扫描、媒体源类型、缓存、关于和断开连接；主题切换在页面右上角。

手机使用 Material 3 底部导航（首页、图片库、影视库、搜索、设置）；宽度达到 840px 后切换为侧边导航。Windows 窗口最小宽度为 960px，因此始终使用侧边导航，并为媒体卡片、横向货架、筛选和图片预览提供键鼠交互。Android TV 使用同一五项目的地组成的左侧导航，内容区以列表级焦点集合管理 D-pad 移动与离屏卡片恢复，详情见上文 Android TV 一节。媒体网格会在 2–5 列间自适应，详情页在宽屏使用双栏布局。默认浅色主题，可在设置页右上角切换深色（TV 默认深色）。

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
