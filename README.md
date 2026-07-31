# Luma

本地/内网的视频、图片与影视库播放器，中文名“轻影”。服务端扫描并索引本地媒体，Flutter 客户端通过用户名和密码登录后浏览、搜索和播放媒体。电影与电视剧目录可以按作品、季和集整理，个人视频和图片继续保留原有文件库体验。

## 影视库

媒体源类型当前固定为 `local`，可指向本地目录或由操作系统挂载的 SMB 目录。每个来源的视频用途可选 `personal`、`movies` 或 `tv`；图片无论来源用途都会进入图片库。历史 `photos` 用途升级后迁为 `personal`。可在 App 的“设置 → 媒体源”中修改视频用途，然后重新扫描。

推荐目录结构：

```text
Movies/流浪地球 2 (2023)/movie.mkv
TV/漫长的季节/Season 01/漫长的季节.S01E01.mkv
```

电影优先使用上级目录作为作品名，并清理常见发布站点、年份、分辨率、编码和语言标记；目录或文件名中的 `[tmdbid-123]` 可作为明确身份。电视剧识别 `SxxExx`、`E03`、`EP03`、`第3集`、受约束的纯数字集号，以及 `Season 02`、`S02`、`第2季`、`Specials` 等季目录。无法可靠识别、重复版本、重复集数或相互冲突的标记会进入待整理。首版仍采用 Direct Play，不包含字幕选择和实时转码。

目录识别后，后端会异步读取标准 `movie.nfo`、同名电影 NFO 或 `tvshow.nfo`，并可选连接 TMDb 获取简介、类型、评分、演职员、海报和背景图。高置信结果自动确认；人工锁定不是刮削前置条件，只在候选不确定或匹配错误时使用。原始 SMB/本地媒体和 NFO 始终只读，下载图片只写入 `storage.cache_dir`。

## 配置影视刮削

直接运行二进制时，修改实际传给 `luma-server -config` 的 YAML：

- 本地开发：复制 `backend/configs/config.example.yaml` 为被 Git 忽略的 `backend/configs/config.yaml`，修改后者。
- Windows：以 `backend/configs/config.windows.example.yaml` 为模板复制一份实际配置。
- Linux：以 `backend/configs/config.example.yaml` 为模板复制到例如 `/etc/luma/config.yaml`。
- Docker：只修改 `backend/.env`；`backend/scripts/docker-deploy.sh` 会根据 `backend/configs/config.docker.yaml` 生成 `.cache/docker/config.yaml`，不要手改生成文件。

本地 NFO 默认启用。要让扫描发现后来新增的 NFO，`media.scan_extensions` 必须包含 `nfo`，新增 NFO 后执行一次正常目录扫描：

```yaml
media:
  scan_extensions: [mp4, mkv, mov, avi, webm, m4v, ts, jpg, jpeg, png, webp, gif, bmp, nfo]

metadata:
  language: zh-CN
  region: CN
  fallback_languages: [en-US]
  refresh_interval: 720h
  request_timeout: 15s
  workers: 1
  requests_per_second: 4
  auto_match_threshold: 90
  auto_match_margin: 8
  proxy_url: ""
  providers:
    nfo:
      enabled: true
    tmdb:
      enabled: true
      options:
        access_token: "TMDb Read Access Token"
        api_base_url: https://api.themoviedb.org/3
        image_base_url: https://image.tmdb.org/t/p/original
```

各字段作用：

| 字段 | 作用 |
| --- | --- |
| `language` / `region` / `fallback_languages` | 首选资料语言、地区及回退语言 |
| `refresh_interval` | 已匹配作品自动刷新周期 |
| `request_timeout` | 单次 Provider 操作超时 |
| `workers` | 后台刮削并发数 |
| `requests_per_second` | 全部在线 Provider 共用的进程级请求速率上限 |
| `auto_match_threshold` | 第一候选达到此分数才允许自动确认；默认 `0`，有候选即自动选择 |
| `auto_match_margin` | 第一候选至少领先第二候选的分差；默认 `0`，不因同分而等待人工确认 |
| `proxy_url` | 可选 HTTP/HTTPS 代理；空值使用 Go 标准环境代理 |
| `providers.nfo.enabled` | 是否读取已扫描到的标准工作级 NFO |
| `providers.tmdb.enabled` | 是否注册 TMDb 在线刮削器 |
| `providers.tmdb.options.access_token` | TMDb API Read Access Token（v4）；启用时必填 |
| `api_base_url` / `image_base_url` | TMDb HTTPS API 和图片基址，通常保持默认 |

Docker 在 `backend/.env` 中使用：

```env
LUMA_TMDB_ENABLED=true
LUMA_TMDB_ACCESS_TOKEN=你的_Read_Access_Token
```

真实 TMDb 访问密钥不应提交到 Git。修改配置后重启服务即可；数据库迁移会自动执行，现有未锁定作品会进入持久化刮削队列，不需要重新挂载 SMB。只有需要发现新文件或新 NFO 时才需要目录扫描。

## 项目结构

- `backend`：Go、Gin、SQLite 服务端，完整架构和 API 说明见 [backend/README.md](backend/README.md)。
- `mobile`：Flutter 手机客户端，运行方式见 [mobile/README.md](mobile/README.md)。

## 部署前准备

通用要求：

- 服务端只适合部署在可信的家庭网络或内网，不要直接暴露到公网。
- 服务端端口默认为 `8080`。
- `/health` 无需认证，其余 `/api/v1` 接口均需要登录后的会话。
- 媒体目录只需要读取权限；数据库、管理员初始密码、缩略图和缓存目录需要写入权限。
- 原始媒体不会被服务端修改、移动或删除。

## 成员账号与目录隐私

首次启动会生成管理员初始密码文件，管理员用户名来自 `security.admin_username`，默认是 `admin`。管理员登录后创建成员账号、设置密码，并授予成员可访问的媒体源。用户名为 3 至 32 个 ASCII 字母、数字、点、下划线或连字符，密码为 10 至 128 个 Unicode 字符且最多 512 个 UTF-8 字节。媒体列表、作品库、详情、缩略图、原图和视频流都会执行同一份来源授权检查；每台安装会使用稳定随机 `device_key` 维持一条可撤销会话，不采集硬件唯一标识。

`security.allowed_roots` 可以配置多条盘符或共享目录，它只是“服务端允许创建来源的安全白名单”，不是用户权限。每个实际目录仍需创建为独立媒体源，之后再按成员授权：

```yaml
security:
  allowed_roots:
    - 'D:\Media'
    - 'E:\FamilyVideos'
    - '\\NAS\Movies'
```

构建管理员工具并创建成员：

```powershell
Set-Location backend
go build -o dist\luma-admin.exe .\cmd\admin
.\dist\luma-admin.exe -username admin -password-file .\data\secrets\admin_password users create -name '家庭成员' -username family -password-file .\family-password.txt
```

来源 ID 可先用 `luma-admin ... sources list` 查询。记下返回的用户 `id` 和来源 `id`，再授予成员来源访问：

```powershell
.\dist\luma-admin.exe -username admin -password-file .\data\secrets\admin_password grants add -user USER_ID -source SOURCE_ID
```

成员在 App 中用账号密码登录。管理员可通过“登录设备”撤销设备会话，或重置密码使该成员所有设备退出登录。管理工具默认只允许通过回环地址上的 HTTP 调用，远程管理应使用 HTTPS；`-allow-insecure` 仅适用于明确受信任的内网。

## Docker Compose 部署（推荐）

要求已安装 Docker Engine 和 Docker Compose 插件。

### 1. 配置 .env

所有 Docker 部署参数只有一个入口：`backend/.env`。复制模板后，填写版本号、端口和媒体目录：

```bash
cd backend
cp .env.example .env
nano .env
```

```env
LUMA_VERSION=0.1.0
LUMA_PORT=8080
LUMA_MEDIA_DIRS=/mnt/TV=tv,/mnt/Movies=movies,/mnt/Photos=photos
```

`LUMA_MEDIA_DIRS` 的每项格式为“宿主机绝对路径=容器目录名”，以英文逗号分隔。部署脚本会将它们只读挂载到 `/media/<容器目录名>`，并自动生成与之匹配的 `security.allowed_roots`；例如上面的目录在 App 中分别填写 `/media/tv`、`/media/movies` 和 `/media/photos`。宿主机必须允许容器中的非特权用户读取媒体文件。

`LUMA_VERSION` 是唯一的 Docker 版本入口：Compose 将它传给 Docker 构建参数，Docker 再用 Go 链接参数注入最终的 `luma-server` 二进制。

### 2. 构建并启动

```bash
cd backend
chmod +x scripts/docker-deploy.sh
./scripts/docker-deploy.sh up -d --build
```

Compose 使用命名卷 `luma-data` 持久化以下内容：

```text
/data/media.db
/data/secrets/admin_password
/data/thumbnails
/data/cache
```

删除容器或重新构建镜像不会删除该命名卷。不要执行 `./scripts/docker-deploy.sh down -v`，除非确认需要删除数据库、管理员初始密码文件和衍生数据。

启动时容器会先读取脚本生成的只读配置，复制到容器临时目录并限制为仅 `luma` 用户可读；随后以 `luma` 用户检查配置、数据目录和 ffmpeg/ffprobe，再正式启动服务。检查失败时容器会退出，具体原因可通过下一步的日志命令查看。

### 3. 检查服务

```bash
./scripts/docker-deploy.sh ps
./scripts/docker-deploy.sh logs -f luma-server
curl http://127.0.0.1:8080/health
```

读取首次启动生成的管理员初始密码：

```bash
./scripts/docker-deploy.sh exec luma-server cat /data/secrets/admin_password
```

### 4. 创建媒体源并扫描

容器内允许的媒体根目录由 `.env` 自动生成；上例中分别是 `/media/tv`、`/media/movies` 和 `/media/photos`。管理员可在 App 的“设置 → 媒体源”中从这些已配置目录选择一个，也可以通过 API 创建。先用管理员账号登录：

```bash
curl -X POST http://127.0.0.1:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"从 admin_password 文件读取的初始密码","device_name":"管理终端"}'
```

将响应中的 `session_token` 赋给环境变量：

```bash
export SESSION_TOKEN='登录响应中的 session_token'

curl -X POST http://127.0.0.1:8080/api/v1/sources \
  -H "Authorization: Bearer ${SESSION_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"电视剧","root_path":"/media/tv"}'
```

使用响应中的 `id` 触发扫描：

```bash
curl -X POST http://127.0.0.1:8080/api/v1/sources/{source_id}/scan \
  -H "Authorization: Bearer ${SESSION_TOKEN}"
```

### 5. 更新和停止

```bash
./scripts/docker-deploy.sh up -d --build
./scripts/docker-deploy.sh stop
./scripts/docker-deploy.sh start
./scripts/docker-deploy.sh down
```

更新前建议停止服务并备份 `luma-data` 命名卷。SQLite 数据库文件、WAL 文件、管理员初始密码文件和配置应作为同一份数据一起备份。

## Linux 二进制部署

要求：

- Go 1.25 或更高版本（仅构建时需要）
- `ffmpeg` 和 `ffprobe`
- 一个可读取媒体、可写数据目录的专用系统用户

### 1. 构建

```bash
cd backend
go test ./...
./scripts/linux-deploy.sh build 0.1.0
```

产物位于（服务端与管理员工具）：

```text
backend/dist/luma-server
backend/dist/luma-admin
```

部署脚本的 `build` 动作默认使用 `CGO_ENABLED=0`，生成不依赖系统 SQLite 动态库的当前平台二进制。

### 2. 准备目录和配置

以下路径仅为示例：

```bash
sudo install -d /etc/luma
sudo cp configs/config.example.yaml /etc/luma/config.yaml
```

编辑 `/etc/luma/config.yaml`，生产部署应使用绝对路径：

```yaml
security:
  admin_username: admin
  admin_password_file: /var/lib/luma/secrets/admin_password
  allowed_origins: []
  allowed_roots:
    - /srv/media

database:
  path: /var/lib/luma/media.db
  busy_timeout_ms: 5000
  wal: true

storage:
  thumbnail_dir: /var/lib/luma/thumbnails
  cache_dir: /var/lib/luma/cache

media:
  ffmpeg_path: /usr/bin/ffmpeg
  ffprobe_path: /usr/bin/ffprobe
```

确保 `luma` 用户可以读取 `/srv/media`，但不需要写入权限。部署脚本会在缺少 `luma` 系统用户时创建它，并负责 `/var/lib/luma` 与 `/opt/luma`。

### 3. 安装、校验并启动

```bash
sudo ./scripts/linux-deploy.sh install
sudo journalctl -u luma -f
```

`install` 会检查配置、数据目录写权限及 `ffmpeg`/`ffprobe`，安装两个二进制，创建或更新 systemd 服务，并启动服务。更新时重新执行 `build` 和 `install`。卸载服务与程序但保留配置和数据：

```bash
sudo ./scripts/linux-deploy.sh uninstall
```

读取管理员初始密码：

```bash
sudo cat /var/lib/luma/secrets/admin_password
```

## Windows 服务部署

要求：

- PowerShell 7+
- Go 1.25 或更高版本（仅构建时需要）
- Windows 版 `ffmpeg.exe` 和 `ffprobe.exe`
- 安装服务时使用管理员 PowerShell

### 1. 构建

```powershell
Set-Location backend
go test ./...
.\scripts\windows-deploy.ps1 -Action BuildServer -Version '0.1.0'
```

产物位于 `backend\dist\luma-server.exe` 和 `backend\dist\luma-admin.exe`。

### 2. 准备配置

```powershell
New-Item -ItemType Directory -Force -Path 'C:\ProgramData\Luma'
Copy-Item '.\configs\config.windows.example.yaml' 'C:\ProgramData\Luma\config.yaml'
```

编辑 `C:\ProgramData\Luma\config.yaml`：

- 将 `security.allowed_roots` 改成真实媒体目录。
- 确认 `ffmpeg_path` 和 `ffprobe_path` 指向实际存在的程序。
- 数据库、管理员密码文件、缩略图和缓存建议继续放在 `C:\ProgramData\Luma`。

手动检查配置：

```powershell
.\dist\luma-server.exe `
  -config 'C:\ProgramData\Luma\config.yaml' `
  -check-config `
  -log-format text
```

### 3. 安装并启动服务

在管理员 PowerShell 中执行：

```powershell
.\scripts\windows-deploy.ps1 -Action InstallServer `
  -Version '0.1.0' `
  -ServiceName 'LumaServer' `
  -ConfigPath 'C:\ProgramData\Luma\config.yaml'
```

安装脚本会：

- 验证管理员权限、配置文件、数据目录和媒体工具。
- 将二进制复制到 `C:\Program Files\Luma\luma-server.exe`。
- 创建或更新 Windows 服务。
- 配置服务失败后的自动重启。
- 启动服务并等待其进入 Running 状态。

查看状态和日志输出：

```powershell
Get-Service LumaServer
Invoke-RestMethod http://127.0.0.1:8080/health
Get-Content 'C:\ProgramData\Luma\secrets\admin_password'
```

服务默认使用 `NT SERVICE\LumaServer` 虚拟服务账户。如果媒体位于 UNC 网络共享，应在 Windows“服务”管理器中改用具有共享读取权限的专用账户，并授予其：

- 读取媒体目录和 ffmpeg 工具的权限。
- 写入 `C:\ProgramData\Luma` 的权限。
- “作为服务登录”权限。

更新服务时重新运行 `windows-deploy.ps1 -Action InstallServer`，脚本会重新构建、停止旧服务、替换稳定安装目录中的二进制并重新启动。已有可信二进制时可加 `-SkipBuild`。

卸载服务：

```powershell
.\scripts\windows-deploy.ps1 -Action UninstallServer -ServiceName 'LumaServer'
```

卸载只删除服务注册，不删除 `C:\ProgramData\Luma` 中的配置、数据库、管理员密码文件、缩略图和缓存，也不删除原始媒体。

## 连接 Flutter 客户端

手机必须能访问服务端所在局域网地址。不要在真机上使用 `127.0.0.1`，应填写服务器局域网 IP 和端口，例如：

```text
IP：192.168.1.10
端口：8080
```

再输入管理员或成员账号的用户名和密码。Android 模拟器访问开发电脑通常使用：

```text
IP：10.0.2.2
端口：8080
```

## 安全与备份

- 不要把管理员初始密码或成员密码提交到 Git、日志或截图中。
- 防火墙只允许可信局域网访问服务端端口。
- 备份时应停止服务，并同时保存 SQLite 数据库、`-wal`、`-shm`、管理员初始密码文件和配置。
- 缩略图和缓存可以重新生成，但一起备份能减少恢复后的处理时间。
- 媒体目录始终单独备份；Luma 不负责备份原始媒体。

## 开发验证

```bash
cd backend
go test ./...
go run ./cmd/server -config configs/config.example.yaml -log-format text
```

Android 构建默认使用 `google()`、Maven Central 和 Gradle Plugin Portal。仅当当前网络无法访问官方仓库时，可设置环境变量 `LUMA_USE_CHINA_MIRRORS=true`，或向 Gradle 传入 `--project-prop "luma.useChinaMirrors=true"`，临时在官方仓库之前加入阿里云镜像。

### 客户端应用信息

Windows 与 Android 客户端的名称、Android application ID、Windows 可执行文件名、公司、作者、版权和版本统一维护在 `mobile/app_metadata.json`。修改该文件后，在 `mobile` 目录执行：

```powershell
dart run tool/sync_app_metadata.dart
```

该命令会生成 Android、Windows 和应用内使用的元数据；`backend/scripts/windows-deploy.ps1 -Action PackageClient` 会先校验生成结果，避免将过期信息打入发行包。

仓库文本默认使用 LF；`.bat`、`.cmd` 和 `.ps1` 使用 CRLF。提交前分别运行 `gofmt`、`dart format`，不要依赖编辑器自动改写整仓行尾。
