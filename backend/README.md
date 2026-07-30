# 本地媒体管理服务端 V1 架构与开发方案

> 当前实现状态：阶段 1 至阶段 6、影视作品层及后端影视刮削基础设施已落地。现已包含项目基建、增量扫描、媒体探测与缩略图、媒体查询、视频 Direct Play、图片原图浏览、电影/剧集聚合、NFO/TMDb 丰富资料，以及收藏、标题、笔记、标签、播放进度和继续观看。用户数据写入使用 revision 乐观锁，用户数据与标签关系在同一事务中更新。

## 快速开始

要求 Go 1.25；执行 `-check-config` 时还要求本机已安装 `ffmpeg` 与 `ffprobe`。本地开发使用 Air `v1.62.0` 热重载 API 服务。

```bash
cd backend
go mod download
cp configs/config.example.yaml configs/config.yaml
go test ./...
sh ./scripts/dev.sh
```

Windows 使用 PowerShell 启动：

```powershell
Copy-Item configs/config.example.yaml configs/config.yaml
.\scripts\dev.ps1
```

开发脚本优先使用 `PATH` 中已安装的 `air`；如果本机尚未安装，则自动通过 `go run github.com/air-verse/air@v1.62.0` 使用固定版本。修改 `cmd`、`internal`、`configs`、`migrations` 或 `api` 下的 Go、YAML、SQL 文件后，Air 会重新构建并重启 API 服务。临时二进制和 Air 日志位于 `.cache/air`，退出时自动清理。生产环境仍直接运行构建后的 `luma-server`，不使用 Air。

服务首次启动会创建 `data/secrets/admin_password`，其中保存一次性的本地管理员初始密码。`GET /health` 无需认证；客户端通过用户名和密码登录，随后以服务端签发的会话访问 API。本地示例媒体目录是 `data/media`，服务端只读它；SQLite 和衍生数据写入独立的 `data` 子目录。

### 多用户、登录会话与媒体源授权

内置 `user_local` 是管理员账号。管理员用 `security.admin_username`（默认 `admin`）和初始密码登录后，可在 App 中创建成员、设置用户名和密码、分配媒体源并管理其登录设备。用户名为 3 至 32 个 ASCII 字母、数字、点、下划线或连字符，密码为 10 至 128 个 Unicode 字符且最多 512 个 UTF-8 字节。成员无授权时默认看不到任何来源，越权访问媒体 ID、缩略图或流地址也统一按不存在处理。

```bash
go build -o dist/luma-admin ./cmd/admin

dist/luma-admin -username admin -password-file data/secrets/admin_password sources list
dist/luma-admin -username admin -password-file data/secrets/admin_password users list
dist/luma-admin -username admin -password-file data/secrets/admin_password users create -name "Alice" -username alice -password-file ./alice-password.txt
dist/luma-admin -username admin -password-file data/secrets/admin_password grants add -user USER_ID -source SOURCE_ID
dist/luma-admin -username admin -password-file data/secrets/admin_password sessions list -user USER_ID
dist/luma-admin -username admin -password-file data/secrets/admin_password sessions revoke -id SESSION_ID
dist/luma-admin -username admin -password-file data/secrets/admin_password users reset-password -id USER_ID -password-file ./new-password.txt
```

也可通过 `LUMA_ADMIN_USERNAME` 和 `LUMA_ADMIN_PASSWORD_FILE` 提供管理员凭据。CLI 首次运行会在用户配置目录生成安装级随机 `device_key`，也可用 `LUMA_ADMIN_DEVICE_KEY_FILE` 或 `-device-key-file` 指定文件；每条命令结束时都会尽力撤销本次会话。所有全局参数必须写在命令之前。管理员 API 位于 `/api/v1/admin/*`，完整请求体和响应见 `api/openapi.yaml`。

远程管理必须使用 HTTPS。CLI 会拒绝对非回环主机使用明文 HTTP，除非显式传入 `-allow-insecure`。设备会话默认有效 30 天，可通过 `security.session_duration` 调整；客户端必须遵守登录响应中的 `expires_at`。数据库升级也会把升级前遗留的永久会话限制为 30 天。客户端可提交最长 64 个字符的安装级随机 `device_key`，同一账号在同一安装中重登会顶替旧会话。撤销会话、重置密码或禁用用户都会使对应设备立即失效。`device_key` 不对外返回，也不能使用硬件唯一标识。`allowed_roots` 支持 YAML 列表中的多个本地盘符或 UNC 根目录，但它只负责路径白名单，成员可见性以 `source_grants` 为准。

### 自动扫描

默认 **开启**（`hybrid`，每 30 分钟兜底扫描）。服务端会在后台自动对**已启用**的本地媒体源调用与手动扫描相同的全量扫描任务（`ScanService.Start`），不新增公开 API：

```yaml
media:
  auto_scan:
    enabled: true
    mode: hybrid    # hybrid | poll | watch
    interval: 30m   # 定时全量兜底 / 刷新监视列表
    debounce: 30s   # 文件系统事件合并窗口（拷贝未完成时避免连扫）
```

| mode | 行为 |
| --- | --- |
| `hybrid`（推荐） | 监视 `root_path` 树；事件经 debounce 后入队；并按 `interval` 全量兜底 |
| `poll` | 仅按 `interval` 对所有启用源尝试扫描 |
| `watch` | 仅依赖目录事件；监听失败时自动退化为 poll |

说明：

- 同一媒体源若已有 `pending`/`running` 扫描，自动触发会被合并（与 API `SCAN_ALREADY_RUNNING` 同一约束）。
- Docker 只读挂载、SMB/NAS 上 inotify 类事件经常不可靠，请依赖 `hybrid`/`poll` 的定时兜底，或把服务跑在能直接看到磁盘事件的主机上。
- App 无需改动；库内容更新后客户端下次刷新列表即可看到。手动「扫描」按钮仍然可用。

常用命令：

```bash
go run ./cmd/server -config configs/config.yaml -check-config
sh ./scripts/build.sh
./scripts/docker-compose.sh up --build
```

`configs/config.example.yaml` 是入库的配置模板；首次开发前将其复制为已被 Git 忽略的 `configs/config.yaml`，后续仅修改本地配置。Windows 可使用 `scripts/dev.ps1`、`scripts/build.ps1`。如需提前安装 Air，可执行 `go install github.com/air-verse/air@v1.62.0`。生产运行应复制示例配置并显式传入路径，不要直接依赖当前工作目录。

### 影视识别与刮削配置

刮削配置位于实际运行 YAML 的 `metadata` 节点，完整字段和部署文件对照见根目录 `README.md` 的“配置影视刮削”。三份入库模板分别是：

- `configs/config.example.yaml`：Linux/通用及本地开发模板；
- `configs/config.windows.example.yaml`：Windows 模板；
- `configs/config.docker.yaml`：Docker 生成模板，其中 TMDb 占位符由 `scripts/docker-compose.sh` 从 `.env` 安全替换。

Docker 部署者只配置 `.env` 的 `LUMA_TMDB_ENABLED` 与 `LUMA_TMDB_ACCESS_TOKEN`。直接部署则在私有 YAML 中设置 `metadata.providers.tmdb.enabled` 和 `metadata.providers.tmdb.options.access_token`。启用 TMDb 但访问密钥为空、Provider options 含未知字段、API/图片基址不是 HTTPS，服务会拒绝启动。配置文件和健康接口不会回显该密钥。

NFO Provider 默认开启。Scanner 将 `.nfo` 单独写入 `catalog_sidecars`，不会把它创建为可播放媒体，也不会修改侧车。只选择标准工作级文件：

- 电影：`movie.nfo`，以及与视频同名的 `.nfo`（同名文件优先级更高）；
- 电视剧：剧集顶层目录的 `tvshow.nfo`。

NFO 可补充本地字段和 `tmdb` 外部 ID；配置 TMDb 后可直接按该 ID 获取线上详情。没有 TMDb 时，NFO 本身仍可独立形成作品资料。

### Scraper 接口和接入约束

可接入刮削器的唯一公共 Go 契约位于 `pkg/scraper/provider.go`。实现至少需要提供基础 `Provider`：

```go
type Provider interface {
    Descriptor() Descriptor
}
```

并按实际能力选择实现 `Searcher`、`ExternalIDResolver`、`WorkFetcher`、`SeasonFetcher`、`EpisodeFetcher`、`ArtworkFetcher`、`SidecarParser`、`HealthChecker`。`Descriptor.Capabilities` 必须与实现的可选接口严格一致，注册表会在启动时拒绝少报、多报、重复 ID 或不支持目标媒体类型的实现。

接入一个新 Provider 需要：

1. 在 `internal/providers/<id>` 实现上述公共接口，只返回 `pkg/scraper` 的标准 DTO，不向 Domain/API 泄露私有响应。
2. 在 `internal/app/metadata.go` 显式构造并注册实现；Luma 不通过配置动态加载任意代码。
3. 在私有配置的 `metadata.providers.<id>` 下增加 `enabled` 和实现所需 `options`，并由实现严格校验未知字段和凭据。
4. 为接口能力、错误分类、超时/取消、凭据不泄露和归一化结果补测试。

在线实现必须使用 Luma 注入的 `http.Client`，从而统一接受请求超时、代理和 `requests_per_second` 限速；图片引用必须保持不透明，由鉴权后的 `/api/v1/catalog/artwork/{id}` 代理读取。Provider 错误使用 `scraper.ProviderError` 分类为未授权、不存在、限流、临时失败、无效响应或不支持，后台任务据此决定安全重试。

人工锁定不是普通刮削的前置步骤。系统以标题、年份和目录共识评分，高置信时自动确认；低置信结果保存在 `catalog_match_candidates`。管理员选择候选后只锁定 Provider 身份，身份锁不会阻止该记录按 `refresh_interval` 更新。

### 本地扫描闭环

以下请求均需携带管理员登录后取得的会话。创建媒体源时 `root_path` 必须位于 `security.allowed_roots` 中；普通媒体源响应不会返回真实路径，管理员可通过 `GET /api/v1/admin/media-roots` 读取可选目录以供客户端选择。

管理界面使用 `POST /api/v1/admin/media-sources` 串联来源创建、初始授权和首次扫描。该入口不宣称跨服务数据库事务：授权或扫描失败时会撤销目标用户的授权、硬删除尚无扫描与媒体记录的来源并级联清除授权；若补偿本身失败，响应会保留原始错误并附带清理错误，便于运维继续处理。已有扫描或媒体索引的正常来源仍使用软删除并保留历史数据。

服务重启采用扫描恢复策略 A：启动时先将上次遗留的 `running` 扫描一次性标记为 `interrupted`，不提交该次扫描的 `missing`，也不自动重试；`pending` 扫描会继续由 Worker 领取。用户可在服务就绪后手动重新发起被中断来源的扫描。扫描与媒体处理恢复全部成功后 HTTP 才开始对外服务，因此就绪探测不会早于持久化状态恢复。

```bash
curl -X POST http://127.0.0.1:8080/api/v1/sources \
  -H "Authorization: Bearer ${SESSION_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"本地媒体","root_path":"/media","library_kind":"personal"}'

curl -X POST http://127.0.0.1:8080/api/v1/sources/{source_id}/scan \
  -H "Authorization: Bearer ${SESSION_TOKEN}"

curl http://127.0.0.1:8080/api/v1/scan-jobs/{scan_id} \
  -H "Authorization: Bearer ${SESSION_TOKEN}"
```

`library_kind` 仅指定目录中视频的用途，可取 `personal`、`movies` 或 `tv`，为空时默认为 `personal`。目录及其子目录中的图片会自动出现在图片库，并继续按媒体源授权控制可见性。旧版 `photos` 来源会在升级时迁为 `personal`。电影源推荐 `片名 (年份)/视频文件`，电视剧源推荐 `剧名/Season 01/剧名.S01E01.mkv`。作品库端点为：

```text
GET   /api/v1/catalog?kind=movie|series
GET   /api/v1/catalog/{id}
PATCH /api/v1/catalog/{id}/user-data
GET   /api/v1/catalog/artwork/{artwork_id}
GET   /api/v1/admin/catalog/{id}/candidates
POST  /api/v1/admin/catalog/{id}/refresh
PUT   /api/v1/admin/catalog/{id}/identity
GET   /api/v1/admin/metadata/status
```

作品索引只写入 SQLite，不移动或修改原始文件；重新扫描只重算未锁定且发生变化的文件。

### 媒体查询

媒体只读端点均需 Bearer 会话。列表默认排除 `missing` 媒体，以及已禁用或软删除来源下的媒体。`sort=duration` 仅含 duration 已稳定的行；`sort=file_size` 仅含 `ready`/`failed`。无 ready 缩略图时 `thumbnail_url` 为空字符串；视频使用 `stream_url`，图片使用 `original_url`，不适用的字段为 `null`。

```bash
curl "http://127.0.0.1:8080/api/v1/media?type=video&sort=created_at&order=desc&limit=50" \
  -H "Authorization: Bearer ${SESSION_TOKEN}"

curl http://127.0.0.1:8080/api/v1/media/{media_id} \
  -H "Authorization: Bearer ${SESSION_TOKEN}"

curl http://127.0.0.1:8080/api/v1/media/{media_id}/thumbnail \
  -H "Authorization: Bearer ${SESSION_TOKEN}" \
  -H 'If-None-Match: "previous-etag"' \
  --output thumbnail.jpg

curl -I http://127.0.0.1:8080/api/v1/media/{media_id}/stream \
  -H "Authorization: Bearer ${SESSION_TOKEN}"

curl http://127.0.0.1:8080/api/v1/media/{media_id}/stream \
  -H "Authorization: Bearer ${SESSION_TOKEN}" \
  -H "Range: bytes=0-1048575" \
  --output video.part

curl http://127.0.0.1:8080/api/v1/media/{image_id}/original \
  -H "Authorization: Bearer ${SESSION_TOKEN}" \
  --output original.jpg
```

列表响应的 `next_cursor` 为 `null` 时表示没有下一页，否则将其原样传入下一次请求。视频 `stream_url` 和图片 `original_url` 均支持 GET、HEAD、Range、`If-None-Match`、`If-Modified-Since` 和 `If-Range`；响应使用私有缓存和基于实际文件大小、修改时间的弱 ETag。媒体列表支持 `favorite` 与 `tag_id` 筛选，用户数据通过 `/user-data` 与 `/progress` 写入。

### Flutter 已封装但暂无前端功能

Flutter 客户端的 `ApiClient` 已封装下列后端接口，但当前 App 没有对应的页面或操作入口。后端接口本身已经实现，不应因客户端暂未使用而删除；后续增加 UI 时直接复用现有客户端请求方法和独立 JSON Decoder。

| 后端能力 | 接口 | Flutter 当前状态 |
| --- | --- | --- |
| 创建媒体源 | `GET /api/v1/admin/media-roots`、`POST /api/v1/admin/media-sources` | App 已提供名称、已配置目录选择、用途和成员授权页面 |
| 编辑媒体源 | `PATCH /api/v1/sources/{id}` | 已封装请求；缺少名称、根目录和启用状态编辑入口 |
| 禁用媒体源 | `DELETE /api/v1/sources/{id}` | 已封装请求；缺少媒体源列表、禁用确认和重新启用入口 |
| 指定媒体源扫描 | `POST /api/v1/sources/{id}/scan` | 已封装并用于扫描；当前按钮会处理所有启用来源，缺少单来源选择入口 |
| 创建标签 | `POST /api/v1/tags` | 已封装请求；缺少标签管理页面 |
| 重命名标签 | `PATCH /api/v1/tags/{id}` | 已封装请求；缺少重命名入口和 revision 冲突提示 |
| 删除标签 | `DELETE /api/v1/tags/{id}` | 已封装请求；缺少删除确认和关联媒体刷新入口 |
| 编辑媒体标签 | `PATCH /api/v1/media/{id}/user-data` 的 `tag_ids` | 用户数据 PATCH 已封装；详情页目前只展示标签，不能添加或移除 |
| 自定义媒体标题 | `PATCH /api/v1/media/{id}/user-data` 的 `custom_title` | 用户数据 PATCH 已封装；缺少标题编辑入口 |

这些缺失项属于 Flutter 产品功能，不是后端接口缺陷。实现顺序继续遵循 `PRODUCT_PLAN.md` 的 P0 → P1 → P2：优先保证连接、媒体浏览、播放和进度闭环，再补媒体源管理、标签编辑和自定义标题。

### 依赖注入基线

项目采用构造函数手动注入，不使用全局容器、Service Locator、Wire 或 Fx。`internal/app/bootstrap.go` 是唯一 Composition Root，依赖创建顺序为：

```text
Config / Logger
→ PathPolicy / SQLite Repositories / SessionAuthenticator / LocalSourceFactory
→ SystemService / SourceService / ScanService / MediaService / StreamService
→ LocalScanner / ScanWorker
→ HealthHandler / SystemHandler / SourceHandler / ScanHandler / MediaHandler / StreamHandler
→ Gin Router
→ http.Server
→ App
```

接口定义在消费方：Service 依赖数据库和路径校验接口，Handler 依赖 UseCase 接口，Router 只接收已经构造好的 Handler 和认证器。创建中途失败或应用关闭时，`cleanupStack` 按依赖创建的相反顺序且仅执行一次清理。测试可分别注入 Fake Pinger、Fake RootValidator 和 Fake UseCase，不需要启动 SQLite、Gin 或真实文件系统。

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

虽然第一版是单用户和局域网优先，服务端仍必须提供账号密码登录、可撤销会话和媒体目录白名单，避免局域网中的未授权设备读取任意文件。

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

除 `/health` 与登录接口外，所有 API 默认要求 Bearer 会话。媒体源根目录必须位于配置的允许目录中；所有文件访问都必须阻止 `..`、绝对路径注入和符号链接逃逸。

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
│   │       ├── user_data_handler.go
│   │       ├── tag_handler.go
│   │       └── optional.go
│   │
│   ├── domain/
│   │   ├── asset.go
│   │   ├── media.go
│   │   ├── source.go
│   │   ├── tag.go
│   │   ├── user_data.go
│   │   ├── job.go
│   │   └── errors.go
│   │
│   ├── service/
│   │   ├── media_service.go
│   │   ├── source_service.go
│   │   ├── scan_service.go
│   │   ├── stream_service.go
│   │   ├── user_data_service.go
│   │   └── tag_service.go
│   │
│   ├── repository/
│   │   ├── media_repository.go
│   │   ├── source_repository.go
│   │   ├── tag_repository.go
│   │   ├── user_data_repository.go
│   │   ├── job_repository.go
│   │   └── sqlite/
│   │       ├── database.go
│   │       ├── migrations.go
│   │       ├── media_repository.go
│   │       ├── source_repository.go
│   │       ├── tag_repository.go
│   │       ├── user_data_repository.go
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
├── .air.toml
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
interrupted
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
* 服务启动时将遗留的扫描 `running` 任务标记为 `interrupted`，保留 `pending` 任务等待执行
* 运行期间按 `workers.lock_timeout` 回收超时锁，并对外部工具施加相同执行超时
* 服务启动与周期恢复会将遗留的 `discovered`/`probing`/`thumbnailing` 媒体重新加入对应任务
* 处理失败的媒体在内容未变时重新扫描仍会重新探测
* 服务退出时取消执行上下文；未完成任务保持 `running`，下次启动由恢复逻辑接管

扫描任务被服务重启中断时只在启动恢复阶段统一标记一次 `interrupted`，不得执行 `missing` 更新，也不自动重试。HTTP 在恢复完成后才就绪，后续由用户手动重新触发扫描。

---

### 7.6 原始媒体模块

内容接口：

```http
GET /api/v1/media/{id}/stream
GET /api/v1/media/{id}/original
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
* 根据打开瞬间的文件大小和秒级修改时间生成稳定的弱 ETag，并与 `Content-Length` 使用同一快照
* 正确处理 `If-None-Match`、`If-Modified-Since` 和 `If-Range`
* 使用适合局域网媒体的 `Cache-Control`，缩略图可长期缓存，原始媒体默认私有缓存
* 缓存已解析的媒体源根路径，避免每个 Range 请求重复 `EvalSymlinks`
* 根目录不可访问时返回 503 `SOURCE_OFFLINE`，不与 `MEDIA_NOT_FOUND` 混淆

安全拼接必须同时验证词法路径和最终解析路径。不能只调用 `filepath.Join`；应使用 `filepath.Clean`、`filepath.Rel` 并检查符号链接解析结果，防止 `..`、绝对路径和链接逃出媒体源。

---

### 7.7 Gin API 模块

Gin 负责路由、HTTP 参数、请求 DTO、响应 DTO 和中间件。使用 `gin.New()` 创建 Engine，不使用带默认日志和恢复逻辑的 `gin.Default()`；项目使用自己的结构化日志和 Recovery。

```go
// 当前已注册路由：
// GET  /health
// GET  /api/v1/system/info
// GET|POST|PATCH|DELETE /api/v1/sources...
// POST /api/v1/sources/:id/scan
// GET  /api/v1/scan-jobs/latest|/api/v1/scan-jobs/:id
// GET  /api/v1/media
// GET  /api/v1/media/:id
// GET  /api/v1/media/:id/thumbnail
// GET|HEAD /api/v1/media/:id/stream
// GET|HEAD /api/v1/media/:id/original
// GET|PATCH /api/v1/media/:id/user-data
// PUT /api/v1/media/:id/progress
// GET /api/v1/media/continue-watching
// GET|POST /api/v1/tags
// PATCH|DELETE /api/v1/tags/:id
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
→ 会话认证（仅 /api/v1，登录接口除外）
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

数据库、WAL、缓存和缩略图不能放在只读媒体目录或网络共享中。管理员初始密码文件需要限制为运行服务的账户和管理员可读；不能假设 `chmod 0600` 在 Windows 上等同于完整 ACL 控制。

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
    content_sha256 TEXT,
    error_message TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(media_id, asset_type, variant, generator_version),
    UNIQUE(storage_key),
    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE
);
```

`storage_key` 是数据目录下的相对键，不允许保存绝对路径或包含 `..`。`content_sha256` 为缩略图文件内容哈希，用于强 ETag 与 304 短路径；旧数据可为空，读取时回退为现算哈希。

### 8.5 media_user_data

```sql
CREATE TABLE media_user_data (
    user_id TEXT NOT NULL,
    media_id TEXT NOT NULL,
    custom_title TEXT,
    favorite INTEGER NOT NULL DEFAULT 0 CHECK (favorite IN (0, 1)),
    notes TEXT,
    -- rating 为历史预留列，V1 API 不读写。
    rating INTEGER CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
    progress_ms INTEGER NOT NULL DEFAULT 0 CHECK (progress_ms >= 0),
    completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
    last_played_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0),
    PRIMARY KEY(user_id, media_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY(media_id) REFERENCES media_items(id) ON DELETE CASCADE
);
```

`revision` 是该用户对该媒体整行用户数据的乐观锁版本（含收藏、标题、笔记与播放进度）。`PATCH /user-data` 与 `PUT /progress` 共用同一版本；任一写入成功后另一路基于旧 `base_revision` 的请求返回 409 `REVISION_CONFLICT`。客户端应使用响应中的新 `revision`（或重新 GET）后重试。删除标签会递增所有仍关联该标签的媒体用户数据版本。

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
    revision INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    UNIQUE(user_id, normalized_name),
    UNIQUE(id, user_id),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

`normalized_name` 由服务端统一执行 Unicode 规范化、去除首尾空白和大小写折叠，用于避免同一用户创建视觉上重复的标签。标签重命名使用独立的 `revision` 乐观锁。

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
Authorization: Bearer {session_token}
```

登录后的会话请求映射到对应 `user_id`。管理员与成员共享同一认证链路，权限和媒体可见性由用户角色与来源授权共同决定。

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

扫描任务响应中的 `status: completed` 和 `phase: completed` 只表示目录遍历、索引写入及 missing 提交完成。ffprobe 和缩略图是后续异步任务，通过同一响应的 `processing` 判断：

```json
{
  "status": "completed",
  "phase": "completed",
  "processing": {
    "status": "running",
    "total": 120,
    "discovered": 3,
    "probing": 1,
    "thumbnailing": 2,
    "ready": 112,
    "failed": 2
  }
}
```

客户端应轮询 `GET /api/v1/scan-jobs/{id}`。`processing.status` 为 `completed` 时全部成功；为 `completed_with_errors` 时处理已全部结束但存在最终失败；为 `running` 时仍有 `discovered`、`probing` 或 `thumbnailing` 媒体。空媒体源在扫描完成后直接返回 `completed`。

处理失败时，服务日志会按 `media_id` 记录 ffprobe 或 ffmpeg 的内部错误，API 仅返回不泄露真实路径的汇总。再次发起来源扫描会重试状态为 `failed` 的媒体；扫描器会忽略 macOS 生成的 `._*` AppleDouble 辅助文件。

### 9.4 媒体列表

```http
GET /api/v1/media
```

参数：

```text
q
type=video|image
favorite=true|false
tag_id
watch_status=unwatched|watching|completed
sort=created_at|filename|duration|file_size
order=asc|desc
cursor
limit（1-100，默认 50）
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
      "original_url": null,
      "favorite": false,
      "progress_ms": 120000,
      "status": "ready"
    }
  ],
  "next_cursor": "cursor_value"
}
```

响应中的 `title` 是已经按 `custom_title → detected_title → filename` 计算后的展示标题，不暴露内部字段选择逻辑给客户端。

`next_cursor` 没有下一页时为 `null`。默认列表排除 `status = missing` 的媒体，同时排除已禁用或软删除来源下的媒体。`watch_status=unwatched` 返回进度为 0 且未完成的媒体（包括没有用户数据的媒体），`watching` 返回进度大于 0 且未完成的媒体，`completed` 返回已完成媒体。视频的 `stream_url` 指向阶段 5 Direct Play 接口且 `original_url` 为 `null`；图片的 `original_url` 指向原图接口且 `stream_url` 为 `null`。`favorite`、`progress_ms`、`completed`、`last_played_at` 和 `user_data_revision` 来自当前用户数据；无记录时使用默认值。没有 `status=ready` 的默认缩略图资产时，`thumbnail_url` 为空字符串。

`created_at` 在 API 中表示 `discovered_at_ms`。所有排序必须追加 `id` 作为稳定的第二排序键，例如：

```text
discovered_at_ms DESC, id DESC
```

为降低处理过程中可变排序键导致的翻页漏项：

* `sort=duration` 仅返回 `duration_ms IS NOT NULL` 或 `status IN (ready, failed)` 的行
* `sort=file_size` 仅返回 `status IN (ready, failed)` 的行
* `sort=created_at` / `filename` 仍包含处理中媒体；完整浏览扫描中的库优先使用这两种排序

Cursor 必须编码排序字段值、媒体 ID、排序方向和筛选条件摘要。修改筛选或排序条件后旧 Cursor 失效。对于可空字段必须固定 NULL 的排列规则。文件 rename 等极端情况下，可变键排序仍可能出现漏项或跳项。

### 9.5 媒体详情

```http
GET /api/v1/media/{id}
```

详情返回列表全部字段，并增加 `source_id`、`mime_type`、`file_size`、`video_codec`、`audio_codec`、`container`、`bitrate`、`frame_rate_num`、`frame_rate_den`、`audio_track_count`、`orientation`、`captured_at`、`created_at` 和 `indexed_at`。不存在、处于 `missing` 状态或属于已禁用/软删除来源的媒体统一返回 404 `MEDIA_NOT_FOUND`。

`GET /api/v1/media/{id}/user-data` 返回完整用户数据和标签；无记录时 `revision` 为 0。`PATCH /api/v1/media/{id}/user-data` 原子修改收藏、自定义标题、笔记和标签关系。请求必须携带 `base_revision`，字段缺失表示保持不变，`custom_title`/`notes` 为 `null` 表示清除，`tag_ids` 表示完整替换。版本不匹配返回 409 `REVISION_CONFLICT`。

### 9.6 缩略图和媒体内容

```http
GET /api/v1/media/{id}/thumbnail
```

接口职责：

```text
/thumbnail：返回当前默认图片资产，适用于视频和图片
```

缩略图返回图片二进制，响应携带强 `ETag`（内容 SHA-256）和 `Cache-Control: private, max-age=604800, must-revalidate`。客户端可发送 `If-None-Match`，匹配时返回 304 且不包含响应体；若资产已持久化内容哈希，304 路径不必读盘。媒体没有可用缩略图资产时返回 404 `THUMBNAIL_NOT_FOUND`；媒体本身不可见时返回 404 `MEDIA_NOT_FOUND`。内容变更触发重新生成时，完成前仍可提供上一份 ready 缩略图。

`GET` 和 `HEAD /api/v1/media/{id}/stream` 仅服务视频原文件。除 `missing` 外的可见视频处理状态均可 Direct Play；响应支持单段 Range、206、416、ETag、Last-Modified 和条件请求。文件定位只使用服务端保存的来源根目录与安全相对路径，打开前后都会验证最终目标仍位于媒体源内。弱 ETag 与 `Content-Length` 均基于打开瞬间的 size/mtime 快照（mtime 截断到秒，与 `Last-Modified` 对齐）；媒体源根目录不可访问时返回 503 `SOURCE_OFFLINE`，原文件缺失返回 404 `MEDIA_NOT_FOUND`。本地媒体源根路径会缓存规范结果，避免每个 Range 请求重复 `EvalSymlinks`。

`GET` 和 `HEAD /api/v1/media/{id}/original` 仅服务图片原文件，支持 JPEG、PNG、WebP、GIF 和 BMP。可见图片无需等待缩略图生成完成即可读取原图；视频请求该接口返回 404。接口与视频流复用相同的安全打开、Range、条件请求、快照 ETag 和来源离线语义，并额外返回 `X-Content-Type-Options: nosniff`。

### 9.7 播放进度

```http
PUT /api/v1/media/{id}/progress
```

请求：

```json
{
  "position_ms": 120000,
  "base_revision": 3
}
```

`position_ms` 与 `base_revision` 均必填。服务端在同一事务内读取可见视频的当前时长：进度不得小于 0；超过时长时截断；达到时长 90% 及以上自动 `completed=true`。进度写入会递增与 `PATCH /user-data` 共用的 `revision`，因此播放心跳与元数据编辑可能互相产生 409，客户端需用最新 revision 重试。非视频返回 422 `MEDIA_NOT_PLAYABLE`；时长尚不可用返回 409 `MEDIA_DURATION_UNAVAILABLE`。

### 9.8 标签

```http
GET    /api/v1/tags
POST   /api/v1/tags
PATCH  /api/v1/tags/{id}
DELETE /api/v1/tags/{id}
```

标签名称使用规范化值做同一用户内的唯一性校验。`PATCH` 重命名必须携带 `base_revision`。删除标签只删除标签关系并递增关联媒体的用户数据 `revision`，不删除媒体。

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
SOURCE_CONFLICT
MEDIA_NOT_FOUND
MEDIA_FILE_MISSING
THUMBNAIL_NOT_FOUND
SCAN_ALREADY_RUNNING
SCAN_NOT_FOUND
TAG_NOT_FOUND
TAG_ALREADY_EXISTS
REVISION_CONFLICT
MEDIA_DURATION_UNAVAILABLE
MEDIA_NOT_PLAYABLE
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
  admin_username: admin
  admin_password_file: /data/secrets/admin_password
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

首次启动时，如果管理员初始密码文件不存在，服务端生成高强度随机密码，并以仅服务进程可读的权限保存。密码不写入普通日志，也不直接存入 YAML。

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
  admin_username: admin
  admin_password_file: 'C:\ProgramData\Luma\secrets\admin_password'
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

可直接执行的 Docker、Linux systemd 和 Windows 服务部署步骤见仓库根目录 [README.md](../README.md)。本节只记录服务端部署约束。

### 12.1 Docker

```bash
cp .env.example .env
# 编辑 LUMA_VERSION、LUMA_PORT 和 LUMA_MEDIA_DIRS。
./scripts/docker-compose.sh up -d --build
```

Docker 部署的唯一用户配置入口是 `.env`。`LUMA_MEDIA_DIRS` 使用 `/host/path=container-name` 的逗号分隔格式；脚本会生成只读挂载与匹配的 `security.allowed_roots`，容器内路径为 `/media/<container-name>`。`LUMA_VERSION` 由 Compose 传入 Docker 构建参数，再由 Go 链接参数写入服务二进制。`docker-compose.yml` 使用命名卷 `luma-data` 持久化 `/data`；容器以非特权用户运行，宿主机媒体目录必须允许该用户读取。Compose 的停止宽限期为 40 秒，应始终长于配置中的 30 秒优雅关闭时间。

目录规划：

```text
/data/
├── media.db
├── thumbnails/
├── cache/
└── secrets/admin_password
```

### 12.2 Windows

Windows 发布包：

```text
luma-server-windows-amd64.zip
├── luma-server.exe
├── luma-admin.exe
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
.\luma-server.exe -config 'C:\ProgramData\Luma\config.yaml' -check-config -log-format text
```

安装脚本默认使用 Windows 服务的 `LocalSystem` 账户，并将二进制复制到稳定的 `C:\Program Files\Luma`。生产环境建议在服务管理器中改用专用低权限账户。该账户需要：

* 数据目录读写权限
* 管理员初始密码文件读取权限
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
* 账号密码登录、会话签发和认证中间件
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

完成（已落地）：

* [x] 媒体列表
* [x] 媒体详情
* [x] 分页
* [x] 稳定 Cursor
* [x] 类型筛选
* [x] 文件名搜索
* [x] 缩略图接口
* [x] OpenAPI 契约
* [x] Gin DTO 绑定、校验和统一错误响应
* [x] Gin Router 集成测试

验收：

```text
客户端能够展示媒体网格
列表接口不返回真实绝对路径
相同 Cursor 不会因并列排序产生重复或遗漏
路由、中间件和认证可通过 httptest 验证
```

### 阶段 5：原始媒体内容

已完成后端实现：

* Stream 接口
* Gin Stream Handler
* HTTP Range
* HEAD
* MIME 类型
* 文件不存在处理
* 路径穿越和符号链接逃逸防护
* ETag、条件请求和缓存策略
* 图片原图 GET/HEAD 接口
* JPEG、PNG、WebP、GIF、BMP MIME 白名单
* 图片 `original_url` 媒体响应字段

真实手机播放器、Windows UNC 和长视频拖动仍需在客户端与部署环境中执行手工验收。

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

已完成后端实现：

* [x] 收藏、笔记和自定义标题
* [x] 标签 CRUD、Unicode 规范化和媒体关联
* [x] 播放进度、90% 自动完成和 revision 冲突保护
* [x] 继续观看稳定分页
* [x] 默认用户和认证 user_id
* [x] 自定义标题与探测标题分离
* [x] 用户数据与标签事务更新
* [x] 收藏与标签媒体筛选

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
* 未认证、错误会话和已撤销会话请求
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
* 除健康检查与登录外的接口需要有效会话
* 无法读取允许目录之外的文件
* Windows x64 可以直接运行、扫描本地盘符和 UNC 来源
* Linux 和 Windows 测试矩阵均通过
