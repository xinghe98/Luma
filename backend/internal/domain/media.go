package domain

import "time"

const (
	// MediaTypeVideo 表示视频文件，对应 media_items.media_type = video。
	MediaTypeVideo = "video"
	// MediaTypeImage 表示图片文件，对应 media_items.media_type = image。
	MediaTypeImage = "image"

	// MediaStatusDiscovered 表示已入库、尚未探测，对应 media_items.status = discovered。
	MediaStatusDiscovered = "discovered"
	// MediaStatusProbing 表示正在执行 ffprobe，对应 media_items.status = probing。
	MediaStatusProbing = "probing"
	// MediaStatusThumbnailing 表示正在生成缩略图，对应 media_items.status = thumbnailing。
	MediaStatusThumbnailing = "thumbnailing"
	// MediaStatusReady 表示探测与默认缩略图均完成，对应 media_items.status = ready。
	MediaStatusReady = "ready"
	// MediaStatusFailed 表示处理重试耗尽后最终失败，对应 media_items.status = failed。
	MediaStatusFailed = "failed"
	// MediaStatusMissing 表示完整扫描未再见到该文件，对应 media_items.status = missing。
	MediaStatusMissing = "missing"

	MediaSortCreatedAt    = "created_at"
	MediaSortFilename     = "filename"
	MediaSortDuration     = "duration"
	MediaSortFileSize     = "file_size"
	MediaSortLastPlayedAt = "last_played_at"
	SortAscending         = "asc"
	SortDescending        = "desc"

	WatchStatusUnwatched = "unwatched"
	WatchStatusWatching  = "watching"
	WatchStatusCompleted = "completed"
)

// Media 表示可安全提供给业务层的媒体索引，不包含任何真实路径。
type Media struct {
	// ID 是媒体唯一标识。
	ID string
	// SourceID 是媒体来源标识。
	SourceID string
	// Filename 是媒体文件名。
	Filename string
	// Title 是媒体展示标题。
	Title string
	// MediaType 是媒体类型。
	MediaType string
	// Status 是媒体处理状态。
	Status string
	// MIMEType 是媒体 MIME 类型。
	MIMEType string
	// VideoCodec 是视频编码格式。
	VideoCodec string
	// AudioCodec 是音频编码格式。
	AudioCodec string
	// Container 是媒体容器格式。
	Container string
	// FileSize 是媒体文件字节数。
	FileSize int64
	// Bitrate 是媒体比特率。
	Bitrate int64
	// DurationMS 是媒体时长（毫秒）。
	DurationMS *int64
	// Width 是媒体宽度（像素）。
	Width *int
	// Height 是媒体高度（像素）。
	Height *int
	// FrameRateNum 是帧率分子。
	FrameRateNum *int
	// FrameRateDen 是帧率分母。
	FrameRateDen *int
	// AudioTrackCount 是音轨数量。
	AudioTrackCount *int
	// Orientation 是媒体方向值。
	Orientation *int
	// CapturedAt 是媒体拍摄时间。
	CapturedAt *time.Time
	// IndexedAt 是媒体索引完成时间。
	IndexedAt *time.Time
	// DiscoveredAt 是媒体发现时间。
	DiscoveredAt time.Time
	// Favorite 表示用户是否已收藏。
	Favorite bool
	// ProgressMS 是用户播放进度（毫秒）。
	ProgressMS int64
	// Completed 表示用户是否已播放完成。
	Completed bool
	// LastPlayedAt 是用户最近播放时间。
	LastPlayedAt *time.Time
	// UserDataRevision 是当前用户数据乐观锁版本；无记录时为 0。
	UserDataRevision int64
	// HasThumbnail 表示存在 status=ready 的默认缩略图资产；仅供 API 组装 thumbnail_url。
	HasThumbnail bool
	// HasCardThumbnail 表示存在 status=ready 的卡片裁剪缩略图资产。
	HasCardThumbnail bool
}

// MediaPageKey 表示 keyset 分页中上一页最后一项的稳定排序位置。
type MediaPageKey struct {
	// StringValue 是字符串排序键值。
	StringValue string
	// IntValue 是整数排序键值。
	IntValue int64
	// Null 表示排序键是否为空。
	Null bool
	// ID 是用于稳定排序的媒体标识。
	ID string
}

// MediaListQuery 表示 Repository 可执行的规范化媒体列表查询。
type MediaListQuery struct {
	// UserID 是查询所属用户标识。
	UserID string
	// Search 是文件名搜索词。
	Search string
	// MediaType 是媒体类型筛选值。
	MediaType string
	// Favorite 是可选收藏状态筛选。
	Favorite *bool
	// TagID 是当前用户的标签筛选。
	TagID string
	// WatchStatus 是当前用户的观看状态筛选。
	WatchStatus string
	// ContinueWatching 表示查询继续观看集合。
	ContinueWatching bool
	// Sort 是排序字段。
	Sort string
	// Order 是排序方向。
	Order string
	// Limit 是查询条数上限。
	Limit int
	// After 是 keyset 分页起点。
	After *MediaPageKey
}

// MediaListRequest 表示 API 业务层接收的原始列表参数。
type MediaListRequest struct {
	// Query 是原始搜索词。
	Query string
	// MediaType 是原始媒体类型筛选值。
	MediaType string
	// Favorite 是可选收藏状态筛选。
	Favorite *bool
	// TagID 是原始标签筛选。
	TagID string
	// WatchStatus 是原始观看状态筛选。
	WatchStatus string
	// ContinueWatching 表示查询继续观看集合。
	ContinueWatching bool
	// Sort 是原始排序字段。
	Sort string
	// Order 是原始排序方向。
	Order string
	// Cursor 是原始分页游标。
	Cursor string
	// Limit 是原始分页条数。
	Limit int
}

// MediaPage 表示一页媒体及可选的下一页 Cursor。
type MediaPage struct {
	// Items 是当前页媒体列表。
	Items []Media
	// NextCursor 是下一页游标；无下一页时为空。
	NextCursor string
}

// ThumbnailAsset 表示当前默认缩略图的安全存储元数据。
type ThumbnailAsset struct {
	// ID 是缩略图资产唯一标识。
	ID string
	// MediaID 是所属媒体标识。
	MediaID string
	// StorageKey 是缩略图存储键。
	StorageKey string
	// MIMEType 是缩略图 MIME 类型。
	MIMEType string
	// ContentSHA256 是缩略图内容摘要。
	ContentSHA256 string
	// GeneratorVersion 是缩略图生成器版本。
	GeneratorVersion int
	// UpdatedAt 是缩略图资产更新时间。
	UpdatedAt time.Time
}

const (
	ThumbnailVariantDefault = "default"
	ThumbnailVariantCard    = "card"
)

// ThumbnailContent 表示缩略图响应内容；NotModified 为 true 时无需响应体。
type ThumbnailContent struct {
	// Data 是缩略图响应数据。
	Data []byte
	// MIMEType 是缩略图 MIME 类型。
	MIMEType string
	// ETag 是缩略图缓存校验标识。
	ETag string
	// NotModified 表示客户端缓存仍然有效。
	NotModified bool
}

// DiscoveredFile 表示扫描器发现并规范化后的媒体文件，写入 media_items 索引列。
type DiscoveredFile struct {
	// RelativePath 写入 media_items.relative_path，相对媒体源根的安全路径。
	RelativePath string
	// Filename 写入 media_items.filename，保留原始大小写的文件名。
	Filename string
	// MediaType 写入 media_items.media_type，取值为 video 或 image。
	MediaType string
	// Size 写入 media_items.file_size，原文件字节数。
	Size int64
	// ModifiedAt 写入 media_items.file_modified_at_ms，原文件最后修改时间。
	ModifiedAt time.Time
	// FileID 写入 media_items.file_id，平台稳定文件身份；不可得时为空。
	FileID string
	// QuickHash 写入 media_items.quick_hash，头尾快速指纹；仅在需要身份匹配时计算。
	QuickHash string
}

// ReconcileResult 表示一次文件发现对 media_items 造成的变化。
type ReconcileResult struct {
	// MediaID 是新建或复用的 media_items.id。
	MediaID string
	// Change 描述索引变化：created、updated、moved 或 unchanged。
	Change string
	// NeedsProbe 为 true 时需重新入队 probe（内容变化、从 missing/failed 恢复等）。
	NeedsProbe bool
}
