# Flutter 影视刮削前端交接

本文冻结本轮后端影视识别/刮削的前端消费边界，供后续 Codex 任务直接续接。本轮没有修改 `mobile/`。后端 OpenAPI 以 `backend/api/openapi.yaml` 为准。

## 后端已提供的能力

- 电影和电视剧扫描后自动进入持久化刮削队列，不要求用户预先人工锁定。
- 自动匹配达到阈值且领先第二候选时直接写入作品资料；否则作品的 `metadata_status` 变为 `needs_review` 并保存候选。
- 支持只读 NFO 和可选 TMDb。Flutter 只能调用 Luma API，不能保存 TMDb Token、拼接 TMDb URL 或解析 Provider 私有响应。
- 人工选择 Provider 身份后设置 `identity_locked=true`，后续目录扫描不会改掉该身份，但定期资料刷新仍会执行。
- Provider 海报和背景图通过 Luma 鉴权端点读取，首次请求由服务端下载并缓存。
- 服务端能力标识增加 `metadata.scrape.v1`。旧服务没有该标识时，客户端必须隐藏刮削管理入口并继续使用原作品字段。

## `CatalogItem` 模型的增量字段

现有作品列表和详情接口不换版本，只增加以下 JSON 字段：

```json
{
  "original_title": "Original title",
  "overview": "简介",
  "tagline": "宣传语",
  "release_date": "2023-01-01",
  "end_date": "",
  "certification": "PG-13",
  "community_rating": 8.4,
  "vote_count": 12345,
  "genres": [{"id": "18", "name": "剧情"}],
  "countries": [{"id": "CN", "name": "中国"}],
  "studios": [{"id": "1", "name": "Studio"}],
  "credits": [{
    "provider_person_id": "123",
    "name": "演员",
    "character": "角色",
    "department": "",
    "job": "",
    "order": 0,
    "profile_url": "/api/v1/catalog/artwork/credit_artwork_xxx"
  }],
  "external_ids": {"tmdb": "123", "imdb": "tt1234567"},
  "metadata_status": "ready",
  "metadata_revision": 2,
  "metadata_error_code": "",
  "provider": "tmdb",
  "provider_item_id": "123",
  "identity_locked": false,
  "favorite": false,
  "favorite_revision": 0,
  "poster_url": "/api/v1/catalog/artwork/artwork_xxx",
  "backdrop_url": "/api/v1/catalog/artwork/artwork_yyy",
  "versions": [{"media_id": "media_4k", "label": "4K · hevc", "file_size": 85469849190, "resolution": "3840×2160", "video_codec": "hevc", "audio_codec": "eac3", "audio_track_count": 2, "selected": true}]
}
```

需要在 `CatalogItem`/DTO/decoder 中增加：

- `originalTitle`、`overview`、`tagline`、`releaseDate`、`endDate`、`certification`
- `communityRating`、`voteCount`
- `genres`、`countries`、`studios`、`credits`、`externalIds`
- `metadataStatus`、`metadataRevision`、`metadataErrorCode`
- `provider`、`providerItemId`、`identityLocked`
- `backdropUrl`
- `favorite`、`favoriteRevision` 与仅电影详情返回的 `versions`

兼容规则：

- 字符串缺失信息使用空字符串；`community_rating` 和既有 `year`/`duration_ms` 可为 `null`。
- 列表解码时将缺失的可选数组/对象按空集合处理，以兼容尚未升级的服务端。
- `poster_url` 仍是统一封面字段，可能指向目录图片、视频缩略图或新的作品图片端点；组件不应判断 URL 类型。
- 新增 `backdrop_url` 为空时，详情页继续使用当前背景策略。
- `credits[].profile_url` 也必须复用带 Token 的图片加载链路。
- `versions` 的 `label` 来自服务端已探测信息，客户端不能自行补出 HDR 等未返回规格。

建议增加以下值对象：

```dart
class CatalogNamedValue {
  // NFO values may not have a Provider ID; decode a missing id as an empty string.
  final String id;
  final String name;
}

class CatalogCredit {
  final String providerPersonId;
  final String name;
  final String character;
  final String department;
  final String job;
  final int order;
  final String profileUrl;
}
```

`metadata_status` 必须容忍未知值，当前已知值：

| 值 | 前端含义 |
| --- | --- |
| `pending` | 已排队，保留现有作品内容，可显示局部“等待刮削” |
| `refreshing` | 后台刷新中，绝不能把已有详情替换为整页 loading |
| `ready` | 资料可用 |
| `needs_review` | 自动匹配不够确定，管理员可选候选 |
| `failed` | 展示 `metadata_error_code` 对应的可重试状态，不展示底层错误或凭据 |

## 新增 API

所有接口仍使用现有 Bearer Token。`/admin/*` 仅管理员可用。

### 读取 Provider 图片

```http
GET /api/v1/catalog/artwork/{artwork_id}
If-None-Match: "<previous etag>"
```

- 响应为图片二进制，支持 `ETag` 和 `304`。
- 必须复用现有带 Token 的图片加载链路，不能交给不带鉴权头的裸 `NetworkImage`。

### 作品级收藏

```http
PATCH /api/v1/catalog/{catalog_id}/user-data
Content-Type: application/json

{"favorite": true, "base_revision": 0}
```

- 收藏属于作品，切换 4K/1080p 版本不会改变状态。
- `base_revision` 使用详情中的 `favorite_revision`；收到 `409` 后重新拉取详情再让用户操作。
- 成功响应包含新的 `favorite`、`revision` 和 `updated_at`。

### 查询待确认候选

```http
GET /api/v1/admin/catalog/{catalog_id}/candidates
```

```json
{
  "items": [{
    "id": "candidate_xxx",
    "provider": "tmdb",
    "provider_item_id": "123",
    "title": "三体",
    "original_title": "三体",
    "year": 2023,
    "overview": "……",
    "score": 88,
    "reasons": ["标题完全匹配", "年份一致"]
  }]
}
```

候选是后端匹配策略产生并持久化的统一结构，不要按 `provider` 分支解析。目前该接口只返回自动任务已经保存的候选，不支持前端传任意搜索词重新搜索。

### 选择并锁定身份

```http
PUT /api/v1/admin/catalog/{catalog_id}/identity
Content-Type: application/json

{
  "provider": "tmdb",
  "provider_item_id": "123",
  "base_revision": 2
}
```

- 成功返回 `204`，后端异步重新获取详情。
- `base_revision` 必须使用作品当前 `metadata_revision`。
- `409` 表示页面数据已过期：保留页面内容，重新拉取作品和候选，再让用户确认；不能静默覆盖。
- 身份选择成功后可立即返回详情页并局部显示 `pending`，不要阻塞等待任务完成。

### 手动刷新

```http
POST /api/v1/admin/catalog/{catalog_id}/refresh
```

或：

```http
POST /api/v1/admin/catalog/refresh
Content-Type: application/json

{"source_id": "source_xxx"}
```

请求体可省略，表示全库刷新。响应：

```json
{"queued_count": 42}
```

刷新是异步操作，`202` 只表示已入队。

### Provider 状态

```http
GET /api/v1/admin/metadata/status
```

```json
{
  "items": [{
    "id": "tmdb",
    "name": "TMDb",
    "enabled": true,
    "capabilities": ["search", "external_id", "work", "season", "episode", "artwork", "health"],
    "available": true,
    "message": ""
  }]
}
```

此接口已经去除凭据。前端只能展示状态，不能编辑或读取服务端 Token。配置仍由部署者修改 YAML/`.env` 并重启。

## 推荐页面与交互改造

1. 扩展作品卡片和详情模型，优先使用 `poster_url`；详情页在有值时展示简介、类型、年份、评分、分级、演职员头像、背景图和电影版本列表。
2. 管理员在 `needs_review` 状态看到“选择匹配”入口。候选页首帧使用路由传入的 `CatalogItem`，后台再请求候选。
3. 选择候选使用确认动作并带 `base_revision`；成功后回到详情，保留当前封面/内容并局部刷新。
4. `failed` 状态提供“重新刮削”，调用单作品刷新端点。不要把 Provider 原始错误直接显示给普通用户。
5. 设置页可增加只读“刮削器状态”，仅在管理员且存在 `metadata.scrape.v1` 时显示。

遵守仓库 UI 约束：

- 列表进入详情时通过路由 `extra` 传递现有作品，首帧不得重新空白加载。
- 元数据刷新保留旧内容，只显示局部进度；错误也不擦除已有资料。
- 作品卡到详情仍按现有视频卡规则使用短 opacity 路由，不新增 Hero。
- 候选确认弹窗关闭后必须移除 barrier、focus 和键盘；`409` 重载不应产生整页闪烁。
- 修改完成后从 `mobile/` 运行 `flutter analyze`、相关 widget/unit tests，并运行 `git diff --check`。

## 后续任务验收清单

- 新旧服务端 JSON 均可解码。
- 普通成员只能查看丰富资料和有权限来源的图片，不能看到管理入口。
- 管理员能处理 `needs_review`、触发刷新和查看 Provider 状态。
- `pending`/`refreshing`/`failed` 均保留已有作品内容。
- 带 Token 图片加载支持 `ETag`，浅色和深色封面均不拉伸。
- 身份选择 `409` 有明确冲突恢复路径。
- 客户端源码中不存在 TMDb Token、TMDb API URL 或 Provider 专用 JSON。
