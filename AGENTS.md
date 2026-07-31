# Luma agent instructions

These rules apply to every change in this repository. They are especially
important for changes under `mobile/`, which is the Flutter application.

## Working agreement

- Preserve unrelated, existing worktree changes. Do not revert or reformat
  unrelated files.
- Prefer the smallest complete fix. Keep deep links and error/retry paths
  working when adding a fast path for in-app navigation.
- For Flutter changes, run `flutter analyze` from `mobile/`, plus focused
  widget/unit tests for the affected feature. Run `git diff --check` before
  handing work off.

## Script inventory contract

- 仓库中受版本控制的 `.sh` 和 `.ps1` 必须始终只保留以下 6 个文件：
  - `backend/scripts/docker-deploy.sh`：仅用于 Linux Docker 部署，同时承载
    Compose 包装和容器入口逻辑。
  - `backend/scripts/linux-deploy.sh`：仅用于 Linux 实体机的构建、安装、
    更新和卸载。
  - `backend/scripts/linux-dev.sh`：仅用于 Linux 本地开发。
  - `backend/scripts/windows-deploy.ps1`：仅用于 Windows 服务端构建、安装、
    更新、卸载及 Windows 客户端 NSIS 安装包构建。
  - `backend/scripts/windows-dev.ps1`：仅用于 Windows 本地开发。
  - `mobile/package-windows.ps1`：仅作为 mobile 目录下一键转发入口，必须调用
    `windows-deploy.ps1 -Action PackageClient`，不得复制打包实现。
- 新的脚本需求必须优先作为参数、动作或内部函数整合进上述对应入口。禁止重新拆出
  `build`、`install-service`、`uninstall-service`、`docker-entrypoint`、
  `package_windows` 等独立脚本，也禁止在 `mobile/tool/` 或其他目录新增 `.sh`
  和 `.ps1`。
- 未经用户明确授权，不得增加、删除、重命名上述脚本，不得改变其平台边界或重新引入
  第七个脚本。Dockerfile、CI、文档和其他调用方必须直接复用上述入口。
- 修改脚本后必须确认仓库脚本清单仍精确为这 6 个文件，检查 Shell/PowerShell
  语法、旧文件名残留引用以及 `git diff --check`；涉及打包流程时继续执行本文件
  规定的平台构建与产物检查。

## Code documentation rules

- 所有新增或修改的代码注释必须使用简洁、自然的中文；避免模板化、冗长或带有 AI 生成痕迹的表述。
- Every new source file must start with a concise header comment describing
  the file's responsibility, its primary collaborators, and any important
  lifecycle or state-management constraint.
- Every new or materially changed public function, method, and callback must
  have a doc comment that states what it does, its important side effects,
  and any non-obvious preconditions or failure behavior.
- Document private functions when their intent is not immediately clear from
  their name and short body. Do not add filler comments that merely restate
  obvious code.
- Keep comments accurate when changing behavior. Updating implementation
  without updating its relevant documentation is incomplete work.

## Flutter page composition

- Page files should own route arguments, lifecycle, loading/error state, and
  mutations only. Move independent display regions such as heroes, metadata
  sections, lists, and tiles into `features/<feature>/widgets/`.
- Do not let a detail page accumulate several unrelated visual components.
  When a page needs multiple display regions, compose dedicated widgets and
  keep shared visual tokens in a nearby theme or token file.

## Android and Windows adaptation contract

`mobile/` 是一套同时面向 Android 与 Windows 10/11 x64 的 Flutter 客户端。
任何页面、组件、导航或播放器改动都必须同时考虑手机触控与 Windows 键鼠；
除非需求明确限定平台，否则只完成一端不算完成。不要为 Windows 复制一套页面，
也不要把手机界面简单放大后当作桌面适配。

### Adaptation layers

- 业务模型、Repository、Controller、路由语义、错误恢复和服务端协议必须共用。
  平台差异应停留在宿主、呈现或输入层，不得分叉业务流程。
- **布局按可用空间判断，不按操作系统判断。** 使用 `LayoutBuilder` 获取局部约束，
  使用 `MediaQuery` 获取视口、DPI、文字缩放和安全区；复用 `LumaLayout` 中已有断点
  和最大宽度。不得用 `Platform.isWindows` 决定网格列数、单双栏、底部导航或侧栏。
- **原生能力才按平台判断。** 窗口尺寸与全屏、系统栏、方向锁定、系统亮度、
  安全存储和关闭生命周期等差异应集中在平台 Controller/adapter 中。页面和普通
  display widget 应接收 `isDesktop`、`canRotate`、`onToggleFullScreen` 等语义能力，
  不要在组件树各处直接读取 `dart:io Platform`。
- **交互按输入设备判断。** 鼠标、键盘、触摸和手写笔行为优先根据
  `PointerDeviceKind`、快捷键和可用回调区分。Windows 设备也可能带触摸屏，
  Android 也可能连接鼠标或键盘；不要把“Windows”等同于“只有鼠标”。
- Hover、右键或快捷键只能增强效率，不能成为核心功能的唯一入口。所有关键动作
  必须保留可见按钮、语义标签和触控路径。

### Responsive layout rules

- 手机保留现有底部导航，达到 `LumaLayout.navigationRailBreakpoint` 后使用
  `NavigationRail`；达到 extended rail 断点后才展开文字。Windows 默认最小窗口
  为 960×640，但 Flutter 布局仍必须能处理测试、窗口恢复或未来宿主提供的更窄约束。
- 页面内容必须使用既有最大宽度约束，避免在 2K/4K 屏幕上无限拉伸。媒体网格继续
  在 2–5 列之间按卡片可读性变化，详情页仅在空间足够时进入双栏。
- 优先使用内容驱动断点。新增断点前先确认现有 `LumaLayout` token 无法表达需求，
  再把新断点加入 token；禁止在多个页面散落相近的 magic number。
- 窄屏选择和筛选使用 bottom sheet，宽屏使用居中 dialog；两端应复用同一个内容
  widget 和返回值，不得维护两套业务逻辑。
- 横向媒体货架同时支持触摸滑动和桌面箭头/键盘翻页。桌面增强不得禁用触摸滚动。
- 所有页面必须检查 320px 手机、390×844 常用手机、平板横竖屏、960×640 Windows
  最小窗口和 1280×800 默认窗口。宽屏内容需有 max-width；窄屏不得溢出或依赖横滚。
- 文字缩放、大字体和中英文混排不得破坏布局。优先让文字安全换行或让次要区域重排，
  不要通过缩小到不可读字号解决溢出。
- Android 与 Windows 的关键触控/点击目标都不小于 48dp。桌面允许更高信息密度，
  但不能缩小核心按钮、返回操作和无障碍焦点区域。
- 主操作按钮在小于 600dp 的窄视口可占满容器；宽屏表单操作使用
  `AdaptiveActionWidth` 限制在 360dp 内，短操作通常限制在 240–280dp，并在所属
  内容区水平居中。不要让按钮随 2K/4K 页面容器无限拉伸或默认贴边。
- 按钮主题的最小尺寸必须用 `Size(0, height)` 表达，不要使用宽度为无限大的
  `Size.fromHeight`。只有操作组明确需要平均分配剩余空间时才在按钮外使用
  `Expanded`，不得把它当作桌面端默认布局。

### Desktop and touch interaction rules

- 可点击媒体卡片必须同时具备鼠标指针、克制的 hover、清晰的键盘 focus，以及
  Enter/Space 激活；不要在封面上增加会干扰 Hero 或浅色/深色图片的持久蒙层。
- 全局桌面快捷键保留 `Ctrl+F` 搜索和 `Alt+Left` 返回。新增快捷键时必须避开
  `TextField`/`SearchBar` 输入冲突，并保留同等可见按钮。
- 连接表单在手机和桌面都保持自然的 Next/Done/Enter 提交流程。桌面端还要验证
  Tab 顺序、初始焦点、错误后的焦点可恢复性。
- Dialog、sheet、popup 和图片预览必须支持按钮关闭、系统 Back/Escape，并在关闭后
  清除 barrier、焦点、键盘和阴影。桌面图片预览保留滚轮、`+`、`-`、`0`、Escape；
  触控端保留双指和双击缩放。
- 不要给同一个动作叠加触摸手势、hover 动画和路由动画三套反馈。每次交互仍遵循
  “一个动作一个主要动效来源”的规则。

### Player adaptation rules

- Android 与 Windows 共用现有 `media_kit`/libmpv 播放链路、认证请求、Range、
  进度保存和错误重试。不要为 Windows 恢复后端实时转码，也不要引入第二套播放器，
  除非有可复现的媒体兼容问题和独立技术决策。
- 移动端保留沉浸系统栏、手机方向控制、触摸三区双击、拖动进度、亮度/系统音量、
  长按倍速和锁定。Windows 保留本地音量/静音、原生窗口全屏、鼠标移动显隐控制层、
  双击全屏和键盘操作。
- Windows 播放器快捷键基线为：Space/K 播放暂停、左右方向键 ±10 秒、上下方向键
  音量 ±5%、M 静音、F 全屏、Escape 先退出全屏再关闭播放器。
- Windows 触摸屏上的触摸事件应继续使用触控语义；不要因为平台是 Windows 就把
  所有 pan/scale 手势禁用。需要区分时在 pointer event 层判断设备种类。
- 全屏页面与迷你播放器必须遵守单一视频纹理不变量：交接前先卸下旧 surface，
  下一帧再挂载新 surface，任何时刻不能让两个 `Video` widget 绑定同一 controller。
- 迷你播放器在手机保留拖动和双指缩放；Windows 增加鼠标拖动、hover 控件和显式
  resize handle。最小化应用窗口不得结束播放，明确关闭或退出应用时必须保存进度
  并释放解码器。
- Windows 窗口关闭使用异步拦截，播放器与进度清理最多等待约 2 秒；清理失败不能
  让窗口永久无法关闭。

### Accepted visual invariants

以下是已确认的跨端设计决定，后续 vibe coding 不得无意回退：

- 首页品牌头部在手机和桌面都让 symbol Logo 与招呼语/副文案横向并排；文字可以
  在自身区域换行，但不要重新把 Logo 独立堆到问候语上方。
- 连接页使用横版品牌 Logo，当前高度为 56dp；没有新的视觉确认时不要缩回较小尺寸。
- 电影和电视剧作品详情左上角使用 48×48dp 的圆形返回按钮，深色海报背景上使用
  近白品牌前景色承托深色返回图标；加载、陈旧内容和刷新失败状态都要保留返回能力。
- 手机的现有自定义底部导航及动效是基线；Windows 只使用其宽屏 rail 分支，不得
  为桌面适配重写或简化手机导航。
- 品牌头部、媒体封面、详情 Hero 和播放器控制层继续遵守 `DESIGN.md` 的配色、
  圆角、间距和动效 token，不得因平台分支形成两套视觉系统。

### Windows host and distribution boundaries

- Windows 使用标准系统标题栏，应用名为“轻影 Luma”，可执行文件为 `luma.exe`；
  默认窗口 1280×800、最小窗口 960×640，并在首次展示时居中。
- Windows 图片缓存基线为 200 项/96MB；Android 继续使用原有手机/平板内存边界。
  调整时必须分别评估低内存 Android 与高 DPI Windows，不得用一个数覆盖两端。
- 首发分发形式为 Windows 10/11 x64 NSIS 安装包（`*-setup.exe`）。安装内容必须
  包含 exe、Flutter 与 plugin DLL、libmpv、Visual C++ runtime、`data`、使用说明
  及第三方/字体许可；由 `windows/installer/luma.nsi` 与
  `windows-deploy.ps1 -Action PackageClient` 生成。
- CI 必须保留 Ubuntu 上的 analyze/test/Android debug build，并在 `windows-latest`
  构建 Windows release 和 NSIS 安装包。除非需求扩展，当前不包含 MSIX、签名、
  自动更新、ARM64、托盘、文件关联或系统媒体键。

### Backend boundary

- 客户端跨端适配默认不修改后端。Android 与 Windows 继续共用 OpenAPI、认证、
  session、GET/HEAD/Range、206/416、媒体地址和播放进度协议。
- 只有 Windows 联调出现可复现的协议或流式兼容问题时，才单独提出后端改动；
  不要以“桌面适配”为由增加平台字段、迁移、转码配置或重复 API。

### Required cross-platform verification

- 每个 UI 改动至少新增或更新一个手机尺寸和一个宽屏尺寸的 widget test；验证布局
  结构，而不只验证文字存在。涉及输入时同时测试 tap 与 keyboard/focus 路径。
- 受影响页面必须在浅色和深色主题检查；媒体卡片和覆盖控件还要检查一张浅色封面
  和一张深色封面。检查 100%、125%、150% Windows DPI 时不能出现裁切或模糊错位。
- 修改平台 adapter、窗口生命周期、播放器、plugin 依赖或打包脚本时，除
  `flutter analyze` 和 focused tests 外，还必须执行 `flutter build apk --debug`
  与 `flutter build windows --release`，并检查 NSIS 安装包/安装目录中的关键
  DLL、许可和 data。
- 普通共享 UI 改动至少运行 `flutter analyze`、相关手机/宽屏 widget tests 和
  `git diff --check`。发布前再运行完整 `flutter test`。
- 不要用生产客户端做自动启动冒烟测试，因为它可能恢复真实凭据并连接用户服务器。
  启动验证必须使用隔离测试配置、mock credential store 或明确授权的测试服务器。
- 手工验收要覆盖鼠标、键盘、触摸（若设备支持）、窗口缩放、最小化/恢复、全屏退出、
  断网重试和冷图片缓存。设备模拟不能替代发布前的 Android 与 Windows 真机检查。

## UI motion and overlay rules

The app must feel immediate and visually clean. Treat a stale frame, lingering
scrim, or whole-page loading flash as a defect.

- Give each interaction one source of motion. Do not stack a route transition,
  Hero flight, dialog fade, keyboard animation, or custom opacity animation
  unless the combined result has been explicitly verified.
- Dialogs and sheets must cleanly remove their barrier, focus, keyboard, and
  shadows when dismissed. Do not leave a semi-transparent overlay or stale
  elevation visible after Cancel or Back.
- Card taps must not add an unintended grey/black splash or overlay. Only add
  a pressed-state effect when it is intentional, brief, and tested against
  light and dark artwork.
- Do not disable all navigation animation by default. Use a no-transition
  route only when a normal route transition demonstrably produces a residual
  or conflicts with another intended animation.

## Navigation and first-frame data rules

- When a list/grid item opens a detail, editor, or action page, pass the
  selected model as route data (`extra` / `initialItem`) and render it on the
  first frame. Refresh complete data in the background.
- A page reached from a deep link may start without route data. It must retain
  a useful app bar and a layout-stable loading state while it fetches.
- Do not re-fetch a list solely to rediscover an object the previous page
  already has. Use the passed object, then refresh only data that is actually
  needed.
- When opening a full list from a summary shelf, pass the visible shelf items
  into the destination and keep them on screen while its first paged refresh
  runs. Do not enter the destination with an empty grid if usable cards are
  already rendered on the source page.
- A refresh must retain existing content. Show a local progress indicator,
  inline status, or top progress line, never replace populated content with a
  full-page loading spinner.

## Loading-state rules

- For an initial page load, use a skeleton whose spacing and hierarchy match
  the resolved page. Do not use a centered, full-page `CircularProgressIndicator`
  when the final page is a list, form, or detail layout.
- Keep loading, empty, error, and ready states separate. An error must not
  erase valid stale content unless that content is known to be invalid.
- Prefer a shared skeleton component over adding one-off loading layouts.

## Media-card rules

- Never stretch artwork. Preserve the source aspect ratio and use an explicit
  `BoxFit`/resize policy appropriate to its card type.
- Decorative controls over artwork, including favorite icons, must remain
  legible on both light and dark covers without adding a persistent opaque
  badge unless the design explicitly requires one.
- A Hero flight from a media card must use the same thumbnail variant at both
  ends of the flight. Do not start decoding a larger detail image until the
  Hero and route transition have settled.
- When the source and destination can resolve the same thumbnail at different
  cache sizes, provide a Hero flight shuttle that keeps the already decoded
  source child. Do not rely on the target image provider becoming ready during
  the flight, and do not swap providers on a fixed timer while the flight is
  still visible.
- Do not use Hero for video-card-to-detail navigation. Use a short,
  opacity-only route transition and defer detail work until it completes;
  this avoids scaling a video cover while the platform is also compositing a
  page transition.
- Do not start a detail request that can replace artwork or notify a shared
  media store during a Hero/route transition. Defer that work until the
  transition finishes, and cancel or ignore it if the destination is gone.
- Image preview routes must initially reuse the source thumbnail. Delay an
  original/full-resolution image request and decode until the Hero and modal
  transition have completed; keep the thumbnail visible until the original is
  ready.
- Before pushing a route, do not emit a global state notification when only a
  detail-cache entry changes. Notify only consumers whose visible data changed,
  otherwise the source page may rebuild during its own outgoing transition.

## Required interaction checks for affected UI

Before declaring a UI change complete, verify the relevant paths:

1. Tap to enter the page or dialog.
2. Dismiss it with Cancel/Back and confirm no overlay, shadow, or keyboard
   residue remains.
3. Load, refresh, and error/retry states, confirming content does not jump
   from a blank page to a full page.
4. Check at least one light and one dark media thumbnail when changing card
   overlays, aspect ratios, or press effects.
5. Profile or at least manually check the first transition with a cold image
   cache when changing Hero, full-resolution image, or shared media-state code.
