# 本地媒体管理服务端 V1 架构与开发方案

## 1. 项目定位

本项目是部署在个人服务器、家庭服务器或内网服务器上的媒体管理后端。

服务端负责：

* 扫描指定本地目录中的视频和图片
* 调用 ffprobe 提取媒体元数据
* 调用 ffmpeg 生成视频缩略图
* 将媒体索引和用户数据保存到 SQLite
* 向客户端提供 REST API
* 提供支持 HTTP Range 的视频流
* 管理收藏、标签、笔记和播放进度
* 提供媒体库扫描状态和异常信息

第一版只支持单用户和本地目录，不处理实时转码、原生 SMB 和复杂权限。

虽然第一版是单用户和局域网优先，服务端仍必须提供最低限度的 API Token 认证和媒体目录白名单，避免局域网中的未授权设备读取任意文件。

---

## 2. 第一版目标

第一版必须跑通以下闭环：

```text
配置本地媒体目录
→ 扫描视频和图片
→ 提取媒体信息
→ 生成缩略图
→ App 获取媒体列表
→ App 展示缩略图
→ 点击视频播放
→ 支持暂停、继续和拖动进度
→ 保存收藏、标签和播放进度
```

---

## 3. 第一版不做的功能

以下功能不进入 V1：

* 服务端实时转码
* HLS 自适应码率
* 原生 SMB 客户端
* AI 图片识别
* 影视信息在线刮削
* 演员和影片数据库
* 多用户权限隔离
* 公网访问
* 自动删除或移动原始文件
* 文件重命名
* 重复文件智能识别
* 多服务器聚合
* Web 管理后台

媒体目录必须以只读方式使用，服务端不得修改原文件。

---

## 4. 技术栈

```text
开发语言：Go
HTTP Server：Go net/http.Server
Web 框架与路由：Gin
视频流：Go http.ServeContent
数据库：SQLite
数据库访问：database/sql + SQLite 驱动
媒体探测：ffprobe
缩略图生成：ffmpeg
配置文件：YAML
日志：结构化日志
接口格式：JSON
依赖注入：构造函数手动注入
部署方式：Docker 优先，同时支持直接运行二进制
服务端平台：Linux 和 Windows
```

Gin 负责路由分组、参数解析、JSON 响应和 API 中间件。底层仍使用 `http.Server` 管理超时和优雅退出。视频流使用 Go 标准库 `http.ServeContent`，它能够处理基于 `io.ReadSeeker` 的内容响应以及 Range、HEAD 和条件请求，不手动解析 Range 请求。

Gin 仅属于 API 适配层，不能进入 Service、Repository、Scanner、Job 或 Domain。官方文档：[Gin 路由](https://gin-gonic.com/en/docs/routing/)、[Gin 中间件](https://gin-gonic.com/en/docs/middleware/)。

---

## 5. 架构原则

### 5.1 原始文件只读

服务端只读取媒体文件，不执行：

* 删除
* 移动
* 重命名
* 修改
* 覆盖

所有缩略图、数据库和缓存均存放在独立的数据目录中。

### 5.2 客户端不能直接访问文件路径

错误方式：

```http
GET /stream?path=/mnt/videos/example.mp4
```

正确方式：

```http
GET /api/v1/media/{mediaId}/stream
```

客户端只知道媒体 ID，真实文件路径只存在于服务端。

### 5.3 扫描和媒体处理异步执行

扫描接口只负责创建任务并立即返回，不等待所有视频处理完成。

```text
POST /api/v1/sources/{id}/scan
→ 返回 scan_job_id
→ 后台执行扫描
→ App 查询任务状态
```

### 5.4 数据库只保存索引和用户数据

媒体原文件仍然保存在用户配置的目录中。

数据库保存：

* 文件相对路径
* 文件大小
* 修改时间
* 媒体元数据
* 缩略图位置
* 处理状态
* 收藏、标签、笔记
* 播放进度

### 5.5 媒体身份与文件路径分离

媒体 ID 是稳定业务标识，不能等同于文件路径。文件改名或在同一媒体源内移动后，应尽量通过文件系统 ID 或快速指纹识别为同一媒体，并保留收藏、标签、笔记和播放进度。

### 5.6 扫描结果必须原子提交

只有当一次扫描完整且成功地遍历媒体源后，才能将本次未发现的记录标记为 `missing`。扫描被取消、服务重启、目录离线或部分子目录读取失败时，不执行批量 `missing` 标记。

### 5.7 时间和路径约定

数据库中的时间统一保存为 UTC Unix 毫秒整数。API 使用 ISO 8601 UTC 字符串。除媒体源配置自身的 `root_path` 外，数据库只保存相对路径或存储键，不保存数据目录、缩略图或缓存的绝对路径。

### 5.8 最低限度安全

除 `/health` 外，所有 API 默认要求 Bearer Token。媒体源根目录必须位于配置的允许目录中；所有文件访问都必须阻止 `..`、绝对路径注入和符号链接逃逸。

### 5.9 Web 框架边界

Gin 只负责 HTTP 协议适配。Handler 将路由参数和请求体转换成业务参数，并将 `c.Request.Context()` 传入 Service。Service 不接收 `*gin.Context`，业务错误也不依赖 Gin 类型。

```text
net/http.Server
→ gin.Engine
→ Gin Middleware
→ Gin Handler
→ Service
→ Repository / MediaSource / Jobs
```

### 5.10 依赖注入和全局状态

第一版采用构造函数手动注入，不引入 Wire、Fx 或 Service Locator。`internal/app` 是唯一 Composition Root，负责按顺序创建依赖、启动 Worker 和 HTTP Server，并按相反顺序关闭资源。

禁止使用全局数据库、全局配置、全局 Service 或在 Handler 内临时创建 Repository。需要替换或测试的外部边界通过接口注入。

### 5.11 跨平台原则

Linux 和 Windows 都是服务端支持平台。业务层统一使用 Go 跨平台 API；文件 ID、路径安全、系统信号和凭据权限等平台差异放在 `internal/platform` 中，通过构建标签或平台实现隔离。

Docker 是 Linux 环境下的优先部署方式；Windows 支持直接运行二进制和后台服务方式。所有正式版本必须同时通过 Linux 与 Windows 测试矩阵。

---

## 6. 推荐目录结构

```text
local-media-server/
├── cmd/
│   └── server/
│       └── main.go
│
├── internal/
│   ├── app/
│   │   ├── app.go
│   │   ├── bootstrap.go
│   │   └── lifecycle.go
│   │
│   ├── config/
│   │   ├── config.go
│   │   └── loader.go
│   │
│   ├── api/
│   │   ├── router.go
│   │   ├── request.go
│   │   ├── response.go
│   │   ├── middleware/
│   │   │   ├── auth.go
│   │   │   ├── logging.go
│   │   │   ├── recover.go
│   │   │   └── cors.go
│   │   └── handler/
│   │       ├── health_handler.go
│   │       ├── media_handler.go
│   │       ├── source_handler.go
│   │       ├── scan_handler.go
│   │       ├── stream_handler.go
│   │       ├── tag_handler.go
│   │       └── progress_handler.go
│   │
│   ├── domain/
│   │   ├── asset.go
│   │   ├── media.go
│   │   ├── source.go
│   │   ├── tag.go
│   │   ├── user.go
│   │   ├── job.go
│   │   └── errors.go
│   │
│   ├── service/
│   │   ├── asset_service.go
│   │   ├── media_service.go
│   │   ├── source_service.go
│   │   ├── scan_service.go
│   │   ├── stream_service.go
│   │   ├── tag_service.go
│   │   └── progress_service.go
│   │
│   ├── repository/
│   │   ├── asset_repository.go
│   │   ├── media_repository.go
│   │   ├── source_repository.go
│   │   ├── tag_repository.go
│   │   ├── user_repository.go
│   │   ├── job_repository.go
│   │   └── sqlite/
│   │       ├── database.go
│   │       ├── migrations.go
│   │       ├── asset_repository.go
│   │       ├── media_repository.go
│   │       ├── source_repository.go
│   │       ├── tag_repository.go
│   │       ├── user_repository.go
│   │       └── job_repository.go
│   │
│   ├── scanner/
│   │   ├── scanner.go
│   │   ├── local_scanner.go
│   │   └── file_filter.go
│   │
│   ├── media/
│   │   ├── probe.go
│   │   ├── ffprobe.go
│   │   ├── thumbnail.go
│   │   └── ffmpeg.go
│   │
│   ├── jobs/
│   │   ├── queue.go
│   │   ├── recovery.go
│   │   ├── worker.go
│   │   └── task.go
│   │
│   ├── platform/
│   │   ├── fileid.go
│   │   ├── fileid_unix.go
│   │   ├── fileid_windows.go
│   │   ├── path.go
│   │   ├── path_unix.go
│   │   └── path_windows.go
│   │
│   └── storage/
│       ├── source.go
│       └── local_source.go
│
├── migrations/
│   └── 001_initial.sql
│
├── configs/
│   ├── config.example.yaml
│   └── config.windows.example.yaml
│
├── api/
│   └── openapi.yaml
│
├── scripts/
│   ├── dev.sh
│   ├── build.sh
│   ├── dev.ps1
│   ├── build.ps1
│   ├── install-service.ps1
│   └── uninstall-service.ps1
│
├── Dockerfile
├── docker-compose.yml
├── go.mod
├── go.sum
└── README.md
```

---

## 7. 核心模块设计

### 7.1 Source 模块

负责管理媒体来源。

第一版只有本地目录：

```go
type Source struct {
    ID            string
    Name          string
    Type          string
    RootPath      string
    ConfigVersion int
    Config         json.RawMessage
    Enabled       bool
    Status        string
    CreatedAt     time.Time
    UpdatedAt     time.Time
}
```

存储源接口：

```go
type MediaSource interface {
    Walk(ctx context.Context, fn func(FileEntry) error) error
    Open(ctx context.Context, relativePath string) (io.ReadSeekCloser, error)
    Stat(ctx context.Context, relativePath string) (FileInfo, error)
    Health(ctx context.Context) (SourceHealth, error)
}
```

第一版实现：

```text
LocalSource
```

后期可增加：

```text
NativeSMBSource
```

优先让操作系统挂载 SMB，再作为 `LocalSource` 使用。宿主机挂载的 SMB 在服务端看来仍是普通目录，不需要单独实现 `MountedSMBSource`；只需要补充在线状态和错误提示。

未来原生 SMB 使用版本化的 `config` 保存主机、端口、共享名和子路径。用户名和密码不得明文写入 `config`，只保存 `credential_ref`，实际凭据由独立的密钥文件或系统密钥服务管理。

Source 状态：

```text
online
offline
degraded
disabled
```

创建或修改本地媒体源时必须：

* 将根目录规范化为绝对路径
* 验证根目录位于 `allowed_roots` 白名单中
* 拒绝不存在、不可读或指向普通文件的根目录
* 不向客户端返回真实根路径

---

### 7.2 Scanner 模块

负责遍历媒体目录并识别媒体文件。

第一版支持扩展名：

```text
视频：
mp4
mkv
mov
avi
webm
m4v
ts

图片：
jpg
jpeg
png
webp
gif
bmp
```

扫描时使用以下字段判断文件是否变化：

```text
source_id
relative_path
file_size
file_modified_at_ms
file_id（可选，inode 或 Windows File ID）
quick_hash（必要时计算）
```

`file_id` 和 `quick_hash` 用于识别改名或移动，不能代替路径唯一约束，也不能作为全局唯一约束。大文件默认不计算完整内容哈希，快速指纹可由文件大小、文件头和文件尾的分块摘要组成。

扫描结果：

```text
新文件：
写入数据库并进入媒体处理队列

已修改文件：
更新文件信息并重新处理

未变化文件：
跳过处理

数据库存在但本次未发现：
仅在本次完整扫描成功后标记为 missing，不直接删除
```

扫描一致性流程：

```text
创建 scan_job 并生成 scan_id
→ 遍历文件
→ 每个成功发现的记录写入 last_seen_scan_id
→ 完整遍历成功
→ 在一个事务中将 last_seen_scan_id != scan_id 的记录标记 missing
→ 提交任务完成状态
```

如果扫描失败、被取消、服务退出、媒体源离线或任意目录无法读取，不执行最后的 `missing` 更新。

改名和移动识别优先级：

```text
source_id + relative_path
→ source_id + file_id
→ source_id + file_size + quick_hash
→ 无法确认时作为新媒体
```

识别为同一媒体时保留原媒体 ID，只更新路径和文件信息。快速指纹冲突或多个候选匹配时不得自动合并。

---

### 7.3 Probe 模块

负责调用 ffprobe。

推荐命令：

```bash
ffprobe \
  -v error \
  -print_format json \
  -show_format \
  -show_streams \
  "/path/to/media"
```

视频需要提取：

```text
时长
宽度
高度
视频编码
音频编码
封装格式
平均码率
帧率
音轨数量
文件大小
```

图片需要提取：

```text
宽度
高度
格式
方向
文件大小
```

常用字段单独保存，完整 ffprobe JSON 保存到 `probe_data`。

帧率使用分子和分母保存，例如 `30000/1001`，不直接使用浮点数。`probe_data` 必须记录解析版本，便于 ffprobe 输出或解析逻辑升级后重新处理。

---

### 7.4 Thumbnail 模块

负责生成缩略图。

视频缩略图示例：

```bash
ffmpeg \
  -ss 00:00:10 \
  -i "/path/to/video.mp4" \
  -frames:v 1 \
  -vf "scale=640:-2" \
  -q:v 3 \
  "/data/thumbnails/{mediaId}.jpg"
```

缩略图时间点策略：

```text
视频少于 30 秒：截取总时长的 20%
视频 30 秒到 20 分钟：截取总时长的 10%
长视频：截取 60 至 120 秒附近
```

缩略图存储键示例：

```text
thumbnails/{mediaId}/cover-640-v1.jpg
```

不得直接使用原始文件名作为缩略图文件名，也不得在数据库中保存 `/data/...` 绝对路径。数据库通过 `media_assets.storage_key` 保存相对于数据目录的存储键。

第一版只生成一张默认封面，但统一使用 `media_assets` 表，为自定义封面、多尺寸缩略图、雪碧图和其他衍生资源预留扩展能力。

---

### 7.5 Job Queue 模块

第一版 Worker 运行在进程内，但任务状态持久化到 SQLite。SQLite 中的 `jobs` 表是任务事实来源，内存队列只负责调度，不是唯一状态来源。

任务类型：

```text
scan_source
probe_media
generate_thumbnail
cleanup_assets
```

任务状态：

```text
pending
running
completed
failed
cancelled
```

媒体状态：

```text
discovered
probing
thumbnailing
ready
failed
missing
```

建议限制并发：

```text
扫描任务：1 个 Worker
ffprobe：2 个 Worker
ffmpeg 缩略图：1 至 2 个 Worker
```

避免同时启动大量 ffmpeg 进程。

任务必须满足：

* 同一媒体、同一任务类型只能有一个有效任务
* Worker 领取任务时写入 `locked_at` 和 `locked_by`
* 失败任务记录 `attempt_count`、`error_code` 和 `error_message`
* ffprobe 和缩略图任务默认最多重试一次
* 任务处理必须幂等，重复执行不得产生重复记录
* 服务启动时将超时的 `running` 任务重新置为 `pending`
* 服务启动时将遗留的 `probing`、`thumbnailing` 媒体重新加入对应任务
* 服务退出时停止领取新任务，并等待正在执行的任务在超时内结束

扫描任务被服务重启中断时标记为 `interrupted`，不得执行 `missing` 更新。后续可以由用户重新触发扫描。

---

### 7.6 Stream 模块

流接口：

```http
GET /api/v1/media/{id}/stream
```

处理流程：

```text
读取媒体 ID
→ 查询数据库
→ 获取 source 和 relative_path
→ 规范化并校验路径仍位于 source 根目录
→ 拒绝符号链接逃逸
→ 检查文件是否存在
→ 打开文件
→ 调用 http.ServeContent
```

核心要求：

* 支持 Range
* 支持 HEAD
* 正确返回 Content-Type
* 文件不存在返回 404
* 不暴露真实路径
* 流接口不经过压缩中间件
* 客户端断开后及时停止读取
* 返回 `Accept-Ranges: bytes`
* 根据文件大小和修改时间生成稳定的弱 ETag
* 正确处理 `If-None-Match`、`If-Modified-Since` 和 `If-Range`
* 使用适合局域网媒体的 `Cache-Control`，缩略图可长期缓存，原始媒体默认私有缓存

安全拼接必须同时验证词法路径和最终解析路径。不能只调用 `filepath.Join`；应使用 `filepath.Clean`、`filepath.Rel` 并检查符号链接解析结果，防止 `..`、绝对路径和链接逃出媒体源。

---

### 7.7 Gin API 模块

Gin 负责路由、HTTP 参数、请求 DTO、响应 DTO 和中间件。使用 `gin.New()` 创建 Engine，不使用带默认日志和恢复逻辑的 `gin.Default()`；项目使用自己的结构化日志和 Recovery。

```go
func NewRouter(
    health *handler.HealthHandler,
    media *handler.MediaHandler,
    sources *handler.SourceHandler,
    scans *handler.ScanHandler,
    tags *handler.TagHandler,
    progress *handler.ProgressHandler,
    stream *handler.StreamHandler,
    auth gin.HandlerFunc,
) *gin.Engine {
    engine := gin.New()
    engine.Use(
        middleware.RequestID(),
        middleware.Recovery(),
        middleware.Logging(),
    )

    engine.GET("/health", health.Get)

    api := engine.Group("/api/v1")
    api.Use(auth)
    {
        api.GET("/media", media.List)
        api.GET("/media/:id", media.Get)
        api.PATCH("/media/:id/user-data", media.UpdateUserData)
        api.PUT("/media/:id/progress", progress.Update)
        api.GET("/media/:id/thumbnail", stream.Thumbnail)
        api.GET("/media/:id/stream", stream.Stream)
        api.HEAD("/media/:id/stream", stream.Stream)

        api.GET("/sources", sources.List)
        api.POST("/sources", sources.Create)
        api.PATCH("/sources/:id", sources.Update)
        api.DELETE("/sources/:id", sources.Delete)
        api.POST("/sources/:id/scan", scans.Start)

        api.GET("/tags", tags.List)
        api.POST("/tags", tags.Create)
        api.PATCH("/tags/:id", tags.Update)
        api.DELETE("/tags/:id", tags.Delete)
    }

    return engine
}
```

Gin Engine 作为标准 `http.Handler` 交给 `http.Server`：

```go
server := &http.Server{
    Addr:              cfg.Server.Address(),
    Handler:           router,
    ReadHeaderTimeout: cfg.Server.ReadHeaderTimeout,
    IdleTimeout:       cfg.Server.IdleTimeout,
}
```

不直接调用 `engine.Run()`，这样可以统一管理超时、监听错误和优雅退出。视频流可能持续很长时间，不设置会截断正常播放的全局短 `WriteTimeout`；如果以后需要写入超时，应对普通 JSON API 和流接口分别设计。

中间件顺序：

```text
Request ID
→ Recovery
→ Structured Logging
→ CORS（仅配置了 Web 来源时）
→ API Token（仅 /api/v1）
→ Handler
```

Gin 的可信代理列表默认设为空。只有明确部署反向代理时才配置受信任的代理地址，不能无条件信任所有 `X-Forwarded-*` 请求头。

Handler 规则：

* 请求结构使用 API DTO，不直接绑定 Domain 或数据库结构体
* 使用 Gin 完成参数读取和 JSON 绑定，再执行显式业务校验
* 将 `c.Request.Context()` 传入 Service，以支持取消和客户端断开
* 统一由响应组件转换业务错误，不在每个 Handler 复制错误 JSON
* 限制 JSON 请求体大小，拒绝未知或非法字段
* Handler 不打开数据库事务，不直接访问 Repository
* Service 和下层模块禁止依赖 `gin.Context`、`gin.H` 或 Gin 错误类型

视频流 Handler 使用：

```go
http.ServeContent(
    c.Writer,
    c.Request,
    content.Name,
    content.ModifiedAt,
    content.Reader,
)
```

流接口不挂载压缩或响应体包装中间件，Handler 调用 `ServeContent` 前不得写入响应体。GET 和 HEAD 都显式注册到同一个 Handler。

API 测试使用 `net/http/httptest` 驱动完整的 Gin Engine，覆盖路由、认证、中间件、错误格式、HEAD 和 Range。

---

### 7.8 依赖注入与应用生命周期

依赖注入使用普通 Go 构造函数。`cmd/server/main.go` 只负责加载启动参数、调用 `app.New`、运行和返回退出码；所有依赖组装集中在 `internal/app/bootstrap.go`。

组装顺序：

```text
Config
→ Logger
→ Clock / ID Generator
→ SQLite Database
→ Repositories
→ Asset Store / MediaSource Factory
→ ffprobe / ffmpeg Process Runner
→ Services
→ Job Queue / Workers
→ Gin Handlers
→ Gin Router
→ http.Server
→ App
```

关闭顺序与创建顺序相反：

```text
停止接收 HTTP 请求
→ 等待在途请求
→ 停止领取新任务
→ 等待或取消正在执行的 Worker
→ 关闭任务队列
→ 关闭数据库
→ 刷新并关闭日志
```

构造函数示例：

```go
func NewMediaService(
    mediaRepo MediaRepository,
    userDataRepo UserDataRepository,
    assetRepo AssetRepository,
    sourceFactory MediaSourceFactory,
    clock Clock,
) *MediaService

type MediaUseCase interface {
    List(ctx context.Context, query MediaQuery) (MediaPage, error)
    Get(ctx context.Context, mediaID string) (MediaDetail, error)
    UpdateUserData(ctx context.Context, command UpdateUserDataCommand) error
}

func NewMediaHandler(service MediaUseCase) *MediaHandler

func NewApp(cfg Config) (*App, error)
```

依赖注入规则：

* 构造函数接收依赖并返回可用对象，缺少必需依赖时立即失败
* 构造函数不启动 Goroutine 或监听端口，运行行为由 `App.Start` 统一触发
* 接口定义在使用方或稳定业务边界，不为每个结构体机械创建接口
* Repository 实现可以是具体类型，但 Service 依赖可替换的 Repository 接口
* ffprobe、ffmpeg、时钟、ID、文件系统和任务调度器必须可替换
* 配置加载完成后视为只读，通过构造函数传递需要的子配置
* 不使用包级可变变量保存数据库、配置、Logger、Service 或 Gin Engine
* 不在请求期间临时组装依赖
* 循环依赖视为模块边界错误，不通过 Service Locator 规避

Bootstrap 使用清理栈记录已经成功创建的资源。如果后续依赖构造失败，必须按相反顺序释放数据库、文件句柄和日志等已创建资源，再返回错误，避免启动失败时泄漏锁和句柄。

测试注入：

```text
Handler 测试：注入 Fake Service 或受控 Service
Service 测试：注入内存 Repository、Fake Clock、Fake ID Generator
扫描测试：注入临时 MediaSource 和 Fake Probe
任务测试：注入 Fake Process Runner，不启动真实 ffmpeg
集成测试：使用临时 SQLite 数据库和真实迁移
```

`App` 持有需要关闭的顶层资源并负责生命周期，业务对象不自行读取环境变量或退出进程。只有 `main` 决定进程退出。

---

### 7.9 Windows 开发与兼容方案

V1 正式支持 Windows x64 直接运行二进制。开发阶段支持控制台启动；正式发布提供 PowerShell 启停脚本和 Windows 后台服务安装说明。Windows ARM64 在建立独立测试矩阵后再列为正式支持。

#### 路径和媒体源

支持以下本地来源：

```text
D:\Media
E:\Photos
\\NAS\Videos
```

作为 Windows 后台服务运行时，用户会话中的映射盘符可能不可见，因此网络共享优先配置 UNC 路径，不推荐使用 `Z:\Videos`。运行服务的账户必须具有对应共享目录的读取权限。

Windows 路径校验必须处理：

* 盘符和 UNC Volume
* 路径大小写不敏感
* `.`、`..` 和混合路径分隔符
* 符号链接、Junction 和其他 Reparse Point
* 中文、空格和长路径
* 不同 Volume 之间无法使用普通相对路径比较的情况

白名单验证使用平台适配器完成规范化和最终目标校验。不能通过简单字符串前缀判断根目录关系；必须比较 Volume，并在解析链接后再次确认目标仍位于允许根目录。

#### 文件身份

文件身份使用平台实现：

```text
Windows：Volume 标识 + File ID
Unix/Linux：device + inode
无法稳定获得文件 ID：file_size + quick_hash
```

平台代码使用构建标签隔离。文件系统或网络共享无法提供稳定 File ID 时自动退回快速指纹，不因为缺少 File ID 阻止扫描。

#### ffmpeg 和 ffprobe

Windows 配置允许显式指定 `.exe`：

```yaml
media:
  ffmpeg_path: 'C:\Tools\ffmpeg\bin\ffmpeg.exe'
  ffprobe_path: 'C:\Tools\ffmpeg\bin\ffprobe.exe'
```

调用外部程序使用 `exec.CommandContext` 并逐个传递参数，不通过 `cmd.exe` 或 PowerShell 拼接命令字符串。这样可以正确处理空格、中文路径并降低命令注入风险。启动时检查可执行文件存在并验证版本命令可以正常运行。

#### SQLite 和数据目录

V1 优先选择无需用户安装 C 编译工具链、可以在 Linux 和 Windows 构建的 SQLite 驱动。如果最终选择依赖 CGO 的驱动，发布流程必须提供完整的 Windows 构建环境和预编译二进制，不能要求普通用户自行安装编译器。

Windows 默认数据目录建议：

```text
C:\ProgramData\Luma\
├── media.db
├── thumbnails\
├── cache\
├── logs\
└── secrets\
```

数据库、WAL、缓存和缩略图不能放在只读媒体目录或网络共享中。Token 文件需要限制为运行服务的账户和管理员可读；不能假设 `chmod 0600` 在 Windows 上等同于完整 ACL 控制。

#### 构建、运行和服务

仓库提供：

```text
scripts/dev.ps1
scripts/build.ps1
scripts/install-service.ps1
scripts/uninstall-service.ps1
configs/config.windows.example.yaml
```

PowerShell 脚本必须使用仓库内的确定路径，不依赖用户当前目录。开发模式使用控制台日志；后台服务模式写结构化文件日志并支持优雅停止。

#### Windows 测试矩阵

每次发布至少验证：

* Windows 上启动、迁移、优雅退出和重启恢复
* `D:\Media`、UNC、中文、空格和长路径
* 路径大小写变化不会创建重复媒体
* Junction/Reparse Point 无法逃出白名单
* Windows File ID 与 quick hash 回退
* ffmpeg/ffprobe 路径包含空格
* 文件被播放器或复制程序占用时扫描不会崩溃
* SQLite WAL、并发 Worker 和异常退出恢复
* GET、HEAD、Range 和客户端中断
* Windows 后台服务账户读取 UNC 共享

CI 至少包含 Linux 与 Windows x64。平台相关测试不得只在 Linux 上使用路径字符串模拟。

---

## 8. 数据库设计

### 8.1 sources

```sql
CREATE TABLE sources (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    source_type TEXT NOT NULL,
    root_path TEXT,
    config_version INTEGER NOT NULL DEFAULT 1,
    config_json TEXT NOT NULL DEFAULT '{}',
    credential_ref TEXT,
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    status TEXT NOT NULL DEFAULT 'online'
        CHECK (status IN ('online', 'offline', 'degraded', 'disabled')),
    last_scan_id TEXT,
    last_seen_at_ms INTEGER,
    deleted_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    CHECK (
        (source_type = 'local' AND root_path IS NOT NULL)
        OR source_type <> 'local'
    )
);
```

第一版只允许 `source_type = local`。操作系统挂载的 SMB 仍使用 `local`。`config_json` 用于未来原生 SMB 等类型的版本化配置，禁止存储明文密码。

### 8.2 users

即使第一版只支持单用户，也创建固定默认用户，避免以后引入多用户时重建所有用户数据表。

```sql
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

INSERT INTO users (id, name, created_at_ms, updated_at_ms)
VALUES ('user_local', 'Local User', 0, 0);
```

迁移代码应使用实际当前时间并保证默认用户插入幂等。

### 8.3 media_items

```sql
CREATE TABLE media_items (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    filename TEXT NOT NULL,
    detected_title TEXT,
    media_type TEXT NOT NULL CHECK (media_type IN ('video', 'image')),
    mime_type TEXT,
    file_size INTEGER NOT NULL CHECK (file_size >= 0),
    file_modified_at_ms INTEGER NOT NULL,
    file_id TEXT,
    quick_hash TEXT,

    duration_ms INTEGER,
    width INTEGER,
    height INTEGER,
    video_codec TEXT,
    audio_codec TEXT,
    container TEXT,
    bitrate INTEGER,
    frame_rate_num INTEGER,
    frame_rate_den INTEGER,
    audio_track_count INTEGER,
    orientation INTEGER,
    captured_at_ms INTEGER,

    probe_data TEXT,
    probe_version INTEGER NOT NULL DEFAULT 1,

    status TEXT NOT NULL CHECK (
        status IN ('discovered', 'probing', 'thumbnailing', 'ready', 'failed', 'missing')
    ),
    error_code TEXT,
    error_message TEXT,
    last_seen_scan_id TEXT,
    missing_at_ms INTEGER,

    discovered_at_ms INTEGER NOT NULL,
    indexed_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,

    UNIQUE(source_id, relative_path),
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE RESTRICT,
    CHECK (duration_ms IS NULL OR duration_ms >= 0),
    CHECK (width IS NULL OR width > 0),
    CHECK (height IS NULL OR height > 0),
    CHECK (frame_rate_den IS NULL OR frame_rate_den > 0)
);
```

字段语义：

```text
file_modified_at_ms：原文件修改时间
discovered_at_ms：第一次进入媒体库的时间，用于“最近添加”
indexed_at_ms：最近一次成功提取元数据的时间
created_at_ms / updated_at_ms：数据库记录时间
last_seen_scan_id：最近一次成功发现该文件的扫描 ID
```

`file_id` 和 `quick_hash` 只用于辅助改名识别，不设置唯一约束。重复文件是合法的，发生多个候选匹配时不得自动合并。

### 8.4 media_assets

所有缩略图、封面、雪碧图等衍生资源统一存储在资产表中。

```sql
CREATE TABLE media_assets (
    id TEXT PRIMARY KEY,
    media_id TEXT NOT NULL,
    asset_type TEXT NOT NULL CHECK (
        asset_type IN ('thumbnail', 'custom_cover', 'sprite', 'preview')
    ),
    variant TEXT NOT NULL DEFAULT 'default',
    storage_key TEXT NOT NULL,
    mime_type TEXT,
    width INTEGER,
    height INTEGER,
    status TEXT NOT NULL CHECK (
        status IN ('pending', 'ready', 'failed')
    ),
    generator_version INTEGER NOT NULL DEFAULT 1,
    error_message TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(media_id, asset_type, variant, generator_version),
    UNIQUE(storage_key),
    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE
);
```

`storage_key` 是数据目录下的相对键，不允许保存绝对路径或包含 `..`。

### 8.5 media_user_data

```sql
CREATE TABLE media_user_data (
    user_id TEXT NOT NULL,
    media_id TEXT NOT NULL,
    custom_title TEXT,
    favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0, 1)),
    notes TEXT,
    rating INTEGER CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
    progress_ms INTEGER NOT NULL DEFAULT 0 CHECK (progress_ms >= 0),
    completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
    last_played_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY(user_id, media_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE
);
```

显示标题按以下顺序计算：

```text
custom_title
→ detected_title
→ filename
```

### 8.6 tags

```sql
CREATE TABLE tags (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(user_id, normalized_name),
    UNIQUE(id, user_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

`normalized_name` 由服务端统一执行 Unicode 规范化、去除首尾空白和大小写折叠，用于避免同一用户创建视觉上重复的标签。

### 8.7 media_tags

```sql
CREATE TABLE media_tags (
    user_id TEXT NOT NULL,
    media_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    PRIMARY KEY(user_id, media_id, tag_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE,
    FOREIGN KEY(tag_id, user_id) REFERENCES tags(id, user_id) ON DELETE CASCADE
);
```

### 8.8 scan_jobs

```sql
CREATE TABLE scan_jobs (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK (
        status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'interrupted')
    ),
    phase TEXT,
    discovered_count INTEGER NOT NULL DEFAULT 0,
    processed_count INTEGER NOT NULL DEFAULT 0,
    failed_count INTEGER NOT NULL DEFAULT 0,
    started_at_ms INTEGER,
    finished_at_ms INTEGER,
    error_code TEXT,
    error_message TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    FOREIGN KEY(id) REFERENCES jobs(id) ON DELETE CASCADE,
    FOREIGN KEY(source_id) REFERENCES sources(id) ON DELETE RESTRICT
);
```

`scan_jobs.id` 与对应的 `jobs.id` 相同，并同时作为 `scan_id` 写入 `media_items.last_seen_scan_id`。`jobs` 是调度状态来源，`scan_jobs` 保存扫描专属进度。只有状态进入 `completed` 前的最终事务可以执行 `missing` 更新。

### 8.9 jobs

```sql
CREATE TABLE jobs (
    id TEXT PRIMARY KEY,
    job_type TEXT NOT NULL CHECK (
        job_type IN ('scan_source', 'probe_media', 'generate_thumbnail', 'cleanup_assets')
    ),
    entity_id TEXT NOT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}',
    status TEXT NOT NULL CHECK (
        status IN ('pending', 'running', 'completed', 'failed', 'cancelled')
    ),
    attempt_count INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 2,
    available_at_ms INTEGER NOT NULL,
    locked_at_ms INTEGER,
    locked_by TEXT,
    error_code TEXT,
    error_message TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    finished_at_ms INTEGER,
    CHECK (attempt_count >= 0),
    CHECK (max_attempts > 0)
);
```

同一实体、同一类型只允许一个活动任务：

```sql
CREATE UNIQUE INDEX idx_jobs_active_entity
ON jobs(job_type, entity_id)
WHERE status IN ('pending', 'running');
```

### 8.10 SQLite 运行参数和索引

数据库初始化时启用 WAL；每个数据库连接都必须启用外键和 busy timeout：

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
```

SQLite 数据库、WAL 文件和任务队列必须放在可靠的本地数据卷中，不得放在 SMB 媒体挂载目录。媒体目录只读，数据库和衍生资产目录可写且与媒体目录隔离。

第一版至少创建以下索引：

```sql
CREATE INDEX idx_media_source_status
ON media_items(source_id, status);

CREATE INDEX idx_media_type_discovered
ON media_items(media_type, discovered_at_ms DESC, id DESC);

CREATE INDEX idx_media_last_seen_scan
ON media_items(source_id, last_seen_scan_id);

CREATE INDEX idx_media_filename
ON media_items(filename);

CREATE INDEX idx_media_assets_media_type
ON media_assets(media_id, asset_type, status);

CREATE INDEX idx_user_data_favorite
ON media_user_data(user_id, favorite, updated_at_ms DESC);

CREATE INDEX idx_user_data_last_played
ON media_user_data(user_id, last_played_at_ms DESC);

CREATE INDEX idx_scan_jobs_source_created
ON scan_jobs(source_id, created_at_ms DESC);

CREATE INDEX idx_jobs_runnable
ON jobs(status, available_at_ms, created_at_ms);
```

所有多表写入必须使用事务，包括：

* 扫描完成与 `missing` 更新
* 修改用户数据与替换标签关系
* 删除媒体索引与清理衍生资源记录
* Worker 领取任务与修改任务状态

### 8.11 删除和保留策略

```text
DELETE 媒体源：默认软删除并禁用，不删除原始文件，也不立即删除媒体索引和用户数据
重新启用同一媒体源：继续使用原 source_id，保留用户数据
明确执行清除索引：删除 media_items，并通过外键级联删除用户数据、标签关系和资产记录
删除标签：级联删除 media_tags，不影响媒体
missing 媒体：保留媒体 ID、用户数据和资产记录
```

第一版 API 不提供清除原始文件的能力。硬清除索引必须是单独、明确且可审计的管理操作。

删除资产数据库记录后，由资产清理任务删除对应的衍生文件。清理任务只能操作数据目录内经过校验的 `storage_key`；失败时保留可重试记录。服务端定期清理数据库中不存在的孤儿衍生文件，但绝不扫描或删除媒体源中的原始文件。

---

## 9. REST API 设计

统一前缀：

```text
/api/v1
```

除 `/health` 外，所有接口必须携带：

```http
Authorization: Bearer {api_token}
```

第一版中通过 Token 的请求统一映射到 `user_local`。以后增加多用户认证时，认证主体映射到不同 `user_id`，业务表和接口结构无需重建。

API 契约使用 OpenAPI 维护，Flutter 客户端和服务端以同一份契约为准。字段删除或语义变化必须通过新的 API 版本完成。

### 9.1 系统接口

```http
GET /health
GET /api/v1/system/info
```

`GET /health` 返回：

```json
{
  "status": "ok",
  "version": "0.1.0"
}
```

`/health` 仅返回存活状态和版本，不返回媒体源路径、配置或其他敏感信息，也不要求认证。`/api/v1/system/info` 需要认证。

### 9.2 媒体源

```http
GET    /api/v1/sources
POST   /api/v1/sources
PATCH  /api/v1/sources/{id}
DELETE /api/v1/sources/{id}
POST   /api/v1/sources/{id}/scan
```

第一版中 `DELETE /api/v1/sources/{id}` 实际执行软删除：将来源设为 `disabled` 并从默认媒体列表隐藏，不删除媒体索引、用户数据或原始文件。重新启用时继续使用原 `source_id`。硬清除索引不复用该接口，后续通过单独的管理操作提供。

创建或修改来源时，服务端只接受位于 `security.allowed_roots` 中的本地目录。API 响应不得返回 `root_path`，只返回来源 ID、名称、类型和状态。

### 9.3 扫描任务

```http
GET /api/v1/scan-jobs/{id}
GET /api/v1/scan-jobs/latest
```

### 9.4 媒体列表

```http
GET /api/v1/media
```

参数：

```text
q
type=video|image
source_id
tag_id
favorite
status
folder
sort=created_at|filename|duration|file_size
order=asc|desc
cursor
limit
```

返回：

```json
{
  "items": [
    {
      "id": "media_001",
      "title": "示例视频",
      "filename": "example.mp4",
      "media_type": "video",
      "duration_ms": 1800000,
      "width": 1920,
      "height": 1080,
      "thumbnail_url": "/api/v1/media/media_001/thumbnail",
      "stream_url": "/api/v1/media/media_001/stream",
      "favorite": false,
      "progress_ms": 120000,
      "status": "ready"
    }
  ],
  "next_cursor": "cursor_value"
}
```

响应中的 `title` 是已经按 `custom_title → detected_title → filename` 计算后的展示标题，不暴露内部字段选择逻辑给客户端。

`created_at` 在 API 中表示 `discovered_at_ms`。所有排序必须追加 `id` 作为稳定的第二排序键，例如：

```text
discovered_at_ms DESC, id DESC
```

Cursor 必须编码排序字段值、媒体 ID、排序方向和筛选条件摘要。修改筛选或排序条件后旧 Cursor 失效。对于可空字段必须固定 NULL 的排列规则。

### 9.5 媒体详情

```http
GET /api/v1/media/{id}
PATCH /api/v1/media/{id}/user-data
```

修改用户数据：

```json
{
  "custom_title": "自定义标题",
  "favorite": true,
  "notes": "以后继续观看",
  "rating": 5,
  "tag_ids": ["tag_1", "tag_2"]
}
```

`custom_title` 写入 `media_user_data`，ffprobe 或文件扫描得到的标题写入 `media_items.detected_title`。`tag_ids` 与其他用户数据必须在同一事务中更新。传入的标签必须属于当前用户。

### 9.6 缩略图和媒体内容

```http
GET /api/v1/media/{id}/thumbnail
GET /api/v1/media/{id}/stream
```

接口职责：

```text
/thumbnail：返回当前默认封面资产，适用于视频和图片
/stream：返回原始媒体内容，视频和原图统一使用该接口
```

第一版不提供语义重复的 `/content`。`/stream` 支持 GET、HEAD、Range 和条件请求。缩略图响应使用基于资产版本的强 ETag 和长期缓存；原始媒体使用基于文件大小与修改时间的弱 ETag，并默认返回私有缓存策略。

### 9.7 播放进度

```http
PUT /api/v1/media/{id}/progress
```

请求：

```json
{
  "position_ms": 120000
}
```

服务端以已探测到的媒体时长为准。进度不得小于 0；超过服务端时长时进行截断。是否标记完成由统一阈值计算，例如播放到 90% 以上。

### 9.8 标签

```http
GET    /api/v1/tags
POST   /api/v1/tags
PATCH  /api/v1/tags/{id}
DELETE /api/v1/tags/{id}
```

标签名称使用规范化值做同一用户内的唯一性校验。删除标签只删除标签关系，不删除媒体。

---

## 10. 统一错误格式

所有接口错误统一返回：

```json
{
  "error": {
    "code": "MEDIA_NOT_FOUND",
    "message": "媒体文件不存在",
    "details": null
  }
}
```

常用错误码：

```text
INVALID_REQUEST
UNAUTHORIZED
FORBIDDEN_PATH
SOURCE_NOT_FOUND
SOURCE_OFFLINE
MEDIA_NOT_FOUND
MEDIA_FILE_MISSING
SCAN_ALREADY_RUNNING
FFPROBE_FAILED
THUMBNAIL_FAILED
INTERNAL_ERROR
```

---

## 11. 配置文件

```yaml
server:
  host: 0.0.0.0
  port: 8080
  read_header_timeout: 10s
  idle_timeout: 60s
  shutdown_timeout: 30s

security:
  api_token_file: /data/secrets/api_token
  allowed_origins: []
  allowed_roots:
    - /media

database:
  path: /data/media.db
  busy_timeout_ms: 5000
  wal: true

storage:
  thumbnail_dir: /data/thumbnails
  cache_dir: /data/cache

media:
  ffmpeg_path: ffmpeg
  ffprobe_path: ffprobe
  thumbnail_width: 640
  scan_extensions:
    - mp4
    - mkv
    - mov
    - avi
    - webm
    - m4v
    - ts
    - jpg
    - jpeg
    - png
    - webp
    - gif
    - bmp

workers:
  scan: 1
  probe: 2
  thumbnail: 1
  lock_timeout: 10m
```

首次启动时，如果 Token 文件不存在，服务端生成高强度随机 Token，并以仅服务进程可读的权限保存。Token 不写入普通日志，也不直接存入 YAML。

`allowed_origins` 为空时不发送 CORS 允许头。移动 App 不依赖浏览器 CORS；只有明确部署 Web 客户端时才配置允许来源。

Windows 示例 `configs/config.windows.example.yaml`：

```yaml
server:
  host: 0.0.0.0
  port: 8080
  read_header_timeout: 10s
  idle_timeout: 60s
  shutdown_timeout: 30s

security:
  api_token_file: 'C:\ProgramData\Luma\secrets\api_token'
  allowed_origins: []
  allowed_roots:
    - 'D:\Media'
    - '\\NAS\Videos'

database:
  path: 'C:\ProgramData\Luma\media.db'
  busy_timeout_ms: 5000
  wal: true

storage:
  thumbnail_dir: 'C:\ProgramData\Luma\thumbnails'
  cache_dir: 'C:\ProgramData\Luma\cache'

media:
  ffmpeg_path: 'C:\Tools\ffmpeg\bin\ffmpeg.exe'
  ffprobe_path: 'C:\Tools\ffmpeg\bin\ffprobe.exe'
  thumbnail_width: 640

workers:
  scan: 1
  probe: 2
  thumbnail: 1
  lock_timeout: 10m
```

Windows 路径在 YAML 中优先使用单引号，避免反斜杠被当作转义字符。生产环境通过启动参数显式指定配置文件，不依赖当前工作目录。

---

## 12. 部署方案

### 12.1 Docker

```yaml
services:
  media-server:
    build: .
    container_name: local-media-server
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./data:/data
      - /mnt/videos:/media/videos:ro
      - /mnt/photos:/media/photos:ro
    environment:
      - TZ=Asia/Shanghai
```

目录规划：

```text
/data/
├── media.db
├── thumbnails/
├── cache/
└── logs/
```

### 12.2 Windows

Windows 发布包：

```text
luma-server-windows-amd64.zip
├── luma-server.exe
├── config.example.yaml
├── install-service.ps1
├── uninstall-service.ps1
└── README-Windows.md
```

首次运行流程：

```text
解压发布包
→ 安装 ffmpeg/ffprobe 或配置现有路径
→ 复制并修改 Windows 示例配置
→ 在控制台执行配置检查
→ 启动服务并确认 /health
→ 按需安装为 Windows 后台服务
```

配置检查命令应只验证配置、目录、数据库可写性和外部程序，不启动长期运行的 HTTP 服务：

```powershell
.\luma-server.exe validate --config 'C:\ProgramData\Luma\config.yaml'
```

后台服务使用专用低权限账户运行。该账户需要：

* 数据目录读写权限
* Token 文件读取权限
* 本地或 UNC 媒体目录只读权限
* ffmpeg 和 ffprobe 执行权限

安装脚本必须可重复执行并明确显示服务账户、配置文件和数据目录，不得静默授予整个磁盘的宽泛权限。卸载服务默认保留数据库、缩略图和配置，删除数据必须是单独且显式的操作。

---

## 13. 开发顺序

### 阶段 1：项目骨架

完成：

* Go 项目初始化
* 配置加载
* 日志
* Gin Engine、路由分组和中间件
* `http.Server` 启动与关闭
* `internal/app` Composition Root
* 构造函数手动依赖注入
* SQLite 初始化
* 数据库迁移
* `/health`
* 默认用户 `user_local`
* API Token 生成和认证中间件
* 媒体目录白名单
* WAL、foreign_keys 和 busy_timeout
* 优雅退出
* Linux Shell 和 Windows PowerShell 开发脚本

验收：

```text
服务能启动
数据库能自动创建
配置错误时给出明确日志
Linux 和 Windows 都能运行 `/health`
Gin Handler 之外的模块不依赖 Gin
应用启动和关闭顺序可由集成测试验证
未认证请求无法访问业务 API
白名单外目录无法创建为媒体源
```

### 阶段 2：本地目录扫描

完成：

* 创建媒体源
* 遍历本地目录
* 识别视频和图片
* 写入 media_items
* 增量扫描
* scan_id 和原子 missing 标记
* 文件 ID 与快速指纹
* 文件改名和移动识别
* Windows 盘符、UNC 和 Reparse Point 处理

验收：

```text
扫描目录后数据库出现媒体记录
重复扫描不会创建重复记录
文件修改后能够重新识别
文件暂时消失不会直接删除用户数据
文件改名后仍保留原媒体 ID 和用户数据
扫描失败或中断不会批量标记 missing
Windows 路径大小写变化不会创建重复媒体
UNC 来源可读取且无法通过 Junction 逃出白名单
```

### 阶段 3：元数据和缩略图

完成：

* ffprobe 调用
* ffprobe JSON 解析
* ffmpeg 缩略图
* `exec.CommandContext` 跨平台进程执行器
* SQLite 持久化任务队列
* media_assets
* 媒体状态更新
* 失败重试一次
* 服务重启任务恢复

验收：

```text
视频能够获得时长和分辨率
视频能够生成缩略图
处理失败不会导致服务崩溃
服务重启后未完成任务能够恢复
数据库中不保存缩略图绝对路径
Windows 可执行文件和媒体路径包含空格时仍能正常处理
```

### 阶段 4：媒体 API

完成：

* 媒体列表
* 媒体详情
* 分页
* 稳定 Cursor
* 类型筛选
* 文件名搜索
* 缩略图接口
* OpenAPI 契约
* Gin DTO 绑定、校验和统一错误响应
* Gin Router 集成测试

验收：

```text
客户端能够展示媒体网格
列表接口不返回真实绝对路径
相同 Cursor 不会因并列排序产生重复或遗漏
路由、中间件和认证可通过 httptest 验证
```

### 阶段 5：视频流

完成：

* Stream 接口
* Gin Stream Handler
* HTTP Range
* HEAD
* MIME 类型
* 文件不存在处理
* 路径穿越和符号链接逃逸防护
* ETag、条件请求和缓存策略

验收：

```text
手机能够播放视频
能够拖动进度条
跳转到视频中间位置时不必重新下载完整文件
GET、HEAD 和条件请求行为正确
无法通过构造路径读取媒体源外文件
Gin 中间件不会压缩、缓冲或截断流响应
```

### 阶段 6：用户数据

完成：

* 收藏
* 标签
* 笔记
* 播放进度
* 继续观看列表
* 默认用户和 user_id
* 自定义标题与探测标题分离
* 用户数据与标签事务更新

验收：

```text
重启服务后用户数据仍然存在
重新扫描不会覆盖用户数据
修改用户数据和标签时不会产生部分成功
```

---

## 14. 第一版测试要求

至少准备以下测试文件：

```text
短 MP4
长 MP4
MKV
竖屏视频
横屏视频
无音轨视频
中文文件名
超长文件名
JPG
PNG
WebP
损坏的视频文件
```

重点测试：

* 重复扫描
* 扫描时服务重启
* 扫描部分目录失败
* 扫描过程中媒体源离线
* ffprobe 执行失败
* ffmpeg 执行失败
* 任务执行时服务重启
* 视频播放中客户端断开
* 视频播放时重新扫描
* 原始文件被移动
* 原始文件被改名
* 两个相同大小文件的快速指纹冲突
* 原始目录暂时不可访问
* 中文路径和空格路径
* Windows 盘符和 UNC 路径
* Windows 路径大小写变化
* Windows 长路径
* Junction 和 Reparse Point
* `..` 路径穿越
* 绝对路径注入
* 指向媒体源外部的符号链接
* 未认证和错误 Token 请求
* 多个客户端同时播放
* SQLite 写入繁忙和并发任务领取
* Cursor 并列排序和翻页期间新增媒体
* Gin 路由分组和中间件执行顺序
* Gin JSON 绑定、未知字段和请求体大小限制
* Gin Recovery 后错误格式与请求 ID
* Composition Root 创建失败时已创建资源正确关闭
* Linux 和 Windows x64 CI
* Windows 后台服务启动、停止和 UNC 权限

---

## 15. V1 完成标准

满足以下条件即可认为后端第一版完成：

* 可以添加一个本地媒体目录
* 使用 Gin 统一管理路由、中间件、参数和响应
* `net/http.Server` 能够优雅启动和关闭 Gin Engine
* 应用依赖由 Composition Root 通过构造函数注入，无全局可变服务
* 可以手动触发扫描
* 可以增量更新媒体索引
* 文件改名或移动后尽量保留媒体 ID 和用户数据
* 扫描失败、中断或媒体源离线不会误标记 missing
* 可以提取视频元数据
* 可以生成缩略图
* 可以查询视频和图片列表
* 可以查询媒体详情
* 可以搜索文件名
* 可以按媒体类型筛选
* 可以通过 HTTP Range 播放视频
* 可以保存收藏、标签、笔记和播放进度
* 用户自定义标题与扫描得到的标题互不覆盖
* 服务重启后数据不丢失
* 服务重启后任务能够恢复或安全重试
* 服务端不修改原始媒体文件
* 数据库不保存可迁移数据目录中的绝对资产路径
* 除健康检查外的接口需要 API Token
* 无法读取允许目录之外的文件
* Windows x64 可以直接运行、扫描本地盘符和 UNC 来源
* Linux 和 Windows 测试矩阵均通过
