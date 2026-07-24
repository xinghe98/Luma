# Luma

本地/内网的视频、图片与影视库播放器，中文名“轻影”。服务端扫描并索引本地媒体，Flutter 客户端通过带 Token 的 API 浏览、搜索和播放媒体。电影与电视剧目录可以按作品、季和集整理，个人视频和图片继续保留原有文件库体验。

## 影视库

媒体源支持四种用途：`personal`、`photos`、`movies` 和 `tv`。旧媒体源升级后默认为 `personal`，不会改变现有媒体展示。可在 App 的“设置 → 媒体源类型”中修改，然后重新扫描。

推荐目录结构：

```text
Movies/流浪地球 2 (2023)/movie.mkv
TV/漫长的季节/Season 01/漫长的季节.S01E01.mkv
```

电影优先使用上级目录作为作品名，电视剧识别 `SxxExx`。无法可靠识别、重复版本或重复集数会进入“设置 → 待整理文件”，人工修正会被锁定，后续扫描不会覆盖。首版仍采用 Direct Play，不包含字幕选择和实时转码。

## 项目结构

- `backend`：Go、Gin、SQLite 服务端，完整架构和 API 说明见 [backend/README.md](backend/README.md)。
- `mobile`：Flutter 手机客户端，运行方式见 [mobile/README.md](mobile/README.md)。

## 部署前准备

通用要求：

- 服务端只适合部署在可信的家庭网络或内网，不要直接暴露到公网。
- 服务端端口默认为 `8080`。
- `/health` 无需认证，其余 `/api/v1` 接口均需要 API Token。
- 媒体目录只需要读取权限；数据库、Token、缩略图和缓存目录需要写入权限。
- 原始媒体不会被服务端修改、移动或删除。

## 成员 Token 与目录隐私

首次启动生成的 `api_token` 是本地管理员根 Token：它可以管理来源、触发扫描、整理作品、创建成员和签发 Token，不应分享给普通成员。成员 Token 只会看到管理员显式授权的媒体源；媒体列表、作品库、详情、缩略图、原图和视频流都会执行同一份来源授权检查。两台设备使用同一个成员 Token 时仍是同一身份，因此也会拥有相同可见范围。

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
.\dist\luma-admin.exe -token-file .\data\secrets\api_token users create -name '家庭成员'
```

更推荐直接使用仓库内的一键签发脚本。脚本会在缺少 `luma-admin` 时自动构建，然后依次创建成员、授权全部指定来源并签发设备 Token：

```powershell
Set-Location backend
.\scripts\issue-family-token.ps1 `
  -Name '家庭成员' `
  -SourceId 'source_movies','source_family' `
  -TokenName 'Alice 手机'
```

```bash
cd backend
sh ./scripts/issue-family-token.sh \
  --name '家庭成员' \
  --source source_movies \
  --source source_family \
  --token-name 'Alice 手机'
```

来源 ID 可先用 `luma-admin ... sources list` 查询。给已有成员增加设备时，PowerShell 改用 `-UserId USER_ID`，Shell 改用 `--user-id USER_ID`，这样不会重复创建成员。可分别使用 `-ExpiresAt` / `--expires` 设置 RFC3339 过期时间。

记下返回的用户 `id` 和 `GET /api/v1/sources` 返回的来源 `id`，授予来源后签发设备 Token：

```powershell
.\dist\luma-admin.exe -token-file .\data\secrets\api_token grants add -user USER_ID -source SOURCE_ID
.\dist\luma-admin.exe -token-file .\data\secrets\api_token tokens create -user USER_ID -name '手机'
```

签发响应中的 `token` 明文只出现一次；服务端只保存 SHA-256 摘要。把该成员 Token 填入 Flutter 客户端。可用 `tokens list` 查询令牌 ID，用 `tokens revoke -id TOKEN_ID` 立即吊销；用 `grants remove` 收回来源访问。管理工具默认只允许通过回环地址上的 HTTP 调用，远程管理应使用 HTTPS；`-allow-insecure` 仅适用于明确受信任的内网。

若管理员根 Token 曾被共享，应停止服务，用系统加密随机数生成器替换 `security.api_token_file` 指向文件中的值并重启；旧根 Token 会立即失效：

```powershell
$token = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
Set-Content -LiteralPath 'C:\ProgramData\Luma\secrets\api_token' -Value $token -NoNewline
```

```bash
openssl rand -hex 32 > /var/lib/luma/secrets/api_token
chmod 600 /var/lib/luma/secrets/api_token
```

成员 Token 存在数据库中，不会因更换根 Token 自动失效，应按需逐个吊销。

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
chmod +x scripts/docker-compose.sh
./scripts/docker-compose.sh up -d --build
```

Compose 使用命名卷 `luma-data` 持久化以下内容：

```text
/data/media.db
/data/secrets/api_token
/data/thumbnails
/data/cache
```

删除容器或重新构建镜像不会删除该命名卷。不要执行 `./scripts/docker-compose.sh down -v`，除非确认需要删除数据库、Token 和衍生数据。

### 3. 检查服务

```bash
./scripts/docker-compose.sh ps
./scripts/docker-compose.sh logs -f luma-server
curl http://127.0.0.1:8080/health
```

读取首次启动生成的 Token：

```bash
./scripts/docker-compose.sh exec luma-server cat /data/secrets/api_token
```

### 4. 创建媒体源并扫描

容器内允许的媒体根目录由 `.env` 自动生成；上例中分别是 `/media/tv`、`/media/movies` 和 `/media/photos`。管理员可在 App 的“设置 → 媒体源”中从这些已配置目录选择一个，也可以通过 API 创建：

```bash
export TOKEN='上一步读取的 Token'

curl -X POST http://127.0.0.1:8080/api/v1/sources \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name":"电视剧","root_path":"/media/tv"}'
```

使用响应中的 `id` 触发扫描：

```bash
curl -X POST http://127.0.0.1:8080/api/v1/sources/{source_id}/scan \
  -H "Authorization: Bearer ${TOKEN}"
```

### 5. 更新和停止

```bash
./scripts/docker-compose.sh up -d --build
./scripts/docker-compose.sh stop
./scripts/docker-compose.sh start
./scripts/docker-compose.sh down
```

更新前建议停止服务并备份 `luma-data` 命名卷。SQLite 数据库文件、WAL 文件和 Token 应作为同一份数据一起备份。

## Linux 二进制部署

要求：

- Go 1.24 或更高版本（仅构建时需要）
- `ffmpeg` 和 `ffprobe`
- 一个可读取媒体、可写数据目录的专用系统用户

### 1. 构建

```bash
cd backend
go test ./...
VERSION=0.1.0 ./scripts/build.sh
```

产物位于（服务端与管理员工具）：

```text
backend/dist/luma-server
backend/dist/luma-admin
```

构建脚本默认使用 `CGO_ENABLED=0`，生成不依赖系统 SQLite 动态库的当前平台二进制。

### 2. 准备目录和配置

以下路径仅为示例：

```bash
sudo useradd --system --home /var/lib/luma --shell /usr/sbin/nologin luma
sudo install -d -o luma -g luma /var/lib/luma
sudo install -d /etc/luma /opt/luma
sudo install -m 0755 dist/luma-server /opt/luma/luma-server
sudo cp configs/config.example.yaml /etc/luma/config.yaml
```

编辑 `/etc/luma/config.yaml`，生产部署应使用绝对路径：

```yaml
security:
  api_token_file: /var/lib/luma/secrets/api_token
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

确保 `luma` 用户可以读取 `/srv/media`，但不需要写入权限。

### 3. 部署前检查

```bash
sudo -u luma /opt/luma/luma-server \
  -config /etc/luma/config.yaml \
  -check-config \
  -log-format text
```

该命令会检查配置、数据目录写权限以及 `ffmpeg`、`ffprobe`。

### 4. 使用 systemd 运行

创建 `/etc/systemd/system/luma.service`：

```ini
[Unit]
Description=Luma Media Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=luma
Group=luma
ExecStart=/opt/luma/luma-server -config /etc/luma/config.yaml
Restart=on-failure
RestartSec=5s
TimeoutStopSec=40s
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

启动并设置开机启动：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now luma
sudo systemctl status luma
sudo journalctl -u luma -f
```

读取 Token：

```bash
sudo cat /var/lib/luma/secrets/api_token
```

## Windows 服务部署

要求：

- PowerShell 7+
- Go 1.24 或更高版本（仅构建时需要）
- Windows 版 `ffmpeg.exe` 和 `ffprobe.exe`
- 安装服务时使用管理员 PowerShell

### 1. 构建

```powershell
Set-Location backend
go test ./...
.\scripts\build.ps1 -Version '0.1.0'
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
- 数据库、Token、缩略图和缓存建议继续放在 `C:\ProgramData\Luma`。

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
.\scripts\install-service.ps1 `
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
Get-Content 'C:\ProgramData\Luma\secrets\api_token'
```

服务默认使用 `LocalSystem`。如果媒体位于 UNC 网络共享，应在 Windows“服务”管理器中改用具有共享读取权限的专用账户，并授予其：

- 读取媒体目录和 ffmpeg 工具的权限。
- 写入 `C:\ProgramData\Luma` 的权限。
- “作为服务登录”权限。

更新服务时重新构建并再次运行 `install-service.ps1`，脚本会停止旧服务、替换稳定安装目录中的二进制并重新启动。

卸载服务：

```powershell
.\scripts\uninstall-service.ps1 -ServiceName 'LumaServer'
```

卸载只删除服务注册，不删除 `C:\ProgramData\Luma` 中的配置、数据库、Token、缩略图和缓存，也不删除原始媒体。

## 连接 Flutter 客户端

手机必须能访问服务端所在局域网地址。不要在真机上使用 `127.0.0.1`，应填写服务器局域网 IP 和端口，例如：

```text
IP：192.168.1.10
端口：8080
```

同时输入服务端生成的 API Token。Android 模拟器访问开发电脑通常使用：

```text
IP：10.0.2.2
端口：8080
```

## 安全与备份

- 不要把 API Token 提交到 Git、日志或截图中。
- 防火墙只允许可信局域网访问服务端端口。
- 备份时应停止服务，并同时保存 SQLite 数据库、`-wal`、`-shm`、Token 和配置。
- 缩略图和缓存可以重新生成，但一起备份能减少恢复后的处理时间。
- 媒体目录始终单独备份；Luma 不负责备份原始媒体。

## 开发验证

```bash
cd backend
go test ./...
go run ./cmd/server -config configs/config.example.yaml -log-format text
```
