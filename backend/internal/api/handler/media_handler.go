package handler

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/xinghe98/Luma/backend/internal/api/response"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// MediaUseCase 定义媒体 API Handler 所需的业务能力。
type MediaUseCase interface {
	List(context.Context, domain.MediaListRequest, string) (domain.MediaPage, error)
	Count(context.Context, domain.MediaListRequest, string) (int, error)
	Get(context.Context, string, string) (domain.Media, error)
	Thumbnail(context.Context, string, string, string, string) (domain.ThumbnailContent, error)
}

func (h *MediaHandler) Count(c *gin.Context) {
	var favorite *bool
	if raw, exists := c.GetQuery("favorite"); exists {
		value, err := strconv.ParseBool(raw)
		if err != nil || (raw != "true" && raw != "false") {
			response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "favorite 必须是 true 或 false", nil)
			return
		}
		favorite = &value
	}
	total, err := h.service.Count(c.Request.Context(), domain.MediaListRequest{
		Query: c.Query("q"), MediaType: c.Query("type"), Favorite: favorite,
		TagID: c.Query("tag_id"), WatchStatus: c.Query("watch_status"),
		LibraryKind: c.Query("library_kind"),
	}, c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": total})
}

// MediaHandler 将媒体查询业务适配为 Gin API。
type MediaHandler struct {
	// service 提供媒体查询业务能力。
	service MediaUseCase
}

// NewMediaHandler 创建媒体 API Handler。
func NewMediaHandler(service MediaUseCase) (*MediaHandler, error) {
	if service == nil {
		return nil, errors.New("媒体业务用例不能为空")
	}
	return &MediaHandler{service: service}, nil
}

// Marshal-friendly DTO 字段标签集中定义在显式转换结构中。
type mediaSummaryJSON struct {
	// ID 是媒体唯一标识。
	ID string `json:"id"`
	// Title 是媒体展示标题。
	Title string `json:"title"`
	// Filename 是媒体文件名。
	Filename string `json:"filename"`
	// MediaType 是媒体类型。
	MediaType string `json:"media_type"`
	// LibraryKind 是来源的内容组织类型。
	LibraryKind string `json:"library_kind"`
	// CatalogItemID 是已识别媒体所属的电影或剧集；未识别媒体为 null。
	CatalogItemID *string `json:"catalog_item_id"`
	// DurationMS 是媒体时长（毫秒）。
	DurationMS *int64 `json:"duration_ms"`
	// Width 是媒体宽度（像素）。
	Width *int `json:"width"`
	// Height 是媒体高度（像素）。
	Height *int `json:"height"`
	// ThumbnailURL 是默认缩略图地址。
	ThumbnailURL string `json:"thumbnail_url"`
	// CardThumbnailURL 是 16:10 居中裁剪的卡片缩略图地址。
	CardThumbnailURL string `json:"card_thumbnail_url"`
	// StreamURL 是视频流地址。
	StreamURL *string `json:"stream_url"`
	// OriginalURL 是图片原图地址。
	OriginalURL *string `json:"original_url"`
	// Favorite 表示用户是否已收藏。
	Favorite bool `json:"favorite"`
	// ProgressMS 是用户播放进度（毫秒）。
	ProgressMS int64 `json:"progress_ms"`
	// Completed 表示用户是否已播放完成。
	Completed bool `json:"completed"`
	// LastPlayedAt 是最近播放时间。
	LastPlayedAt *string `json:"last_played_at"`
	// UserDataRevision 是用户数据乐观锁版本。
	UserDataRevision int64 `json:"user_data_revision"`
	// Status 是媒体处理状态。
	Status string `json:"status"`
	// CreatedAt 是媒体首次进入媒体库的时间。
	CreatedAt string `json:"created_at"`
}

type mediaDetailJSON struct {
	// mediaSummaryJSON 嵌入媒体摘要字段。
	mediaSummaryJSON
	// SourceID 是媒体来源标识。
	SourceID string `json:"source_id"`
	// MIMEType 是媒体 MIME 类型。
	MIMEType string `json:"mime_type"`
	// FileSize 是媒体文件字节数。
	FileSize int64 `json:"file_size"`
	// VideoCodec 是视频编码格式。
	VideoCodec string `json:"video_codec"`
	// AudioCodec 是音频编码格式。
	AudioCodec string `json:"audio_codec"`
	// Container 是媒体容器格式。
	Container string `json:"container"`
	// Bitrate 是媒体比特率。
	Bitrate int64 `json:"bitrate"`
	// FrameRateNum 是帧率分子。
	FrameRateNum *int `json:"frame_rate_num"`
	// FrameRateDen 是帧率分母。
	FrameRateDen *int `json:"frame_rate_den"`
	// AudioTrackCount 是音轨数量。
	AudioTrackCount *int `json:"audio_track_count"`
	// Orientation 是媒体方向值。
	Orientation *int `json:"orientation"`
	// CapturedAt 是媒体拍摄时间。
	CapturedAt *string `json:"captured_at"`
	// IndexedAt 是媒体索引完成时间。
	IndexedAt *string `json:"indexed_at"`
}

// List 处理 GET /api/v1/media。
func (h *MediaHandler) List(c *gin.Context) {
	limit, ok := parseMediaLimit(c)
	if !ok {
		return
	}
	var favorite *bool
	if raw, exists := c.GetQuery("favorite"); exists {
		value, err := strconv.ParseBool(raw)
		if err != nil || (raw != "true" && raw != "false") {
			response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "favorite 必须是 true 或 false", nil)
			return
		}
		favorite = &value
	}
	page, err := h.service.List(c.Request.Context(), domain.MediaListRequest{
		Query: c.Query("q"), MediaType: c.Query("type"), Sort: c.Query("sort"),
		Order: c.Query("order"), Cursor: c.Query("cursor"), Limit: limit,
		Favorite: favorite, TagID: c.Query("tag_id"), WatchStatus: c.Query("watch_status"),
		LibraryKind: c.Query("library_kind"),
	}, c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	items := make([]mediaSummaryJSON, 0, len(page.Items))
	for _, item := range page.Items {
		items = append(items, presentMediaSummary(item))
	}
	var nextCursor any
	if page.NextCursor != "" {
		nextCursor = page.NextCursor
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "next_cursor": nextCursor})
}

// ContinueWatching 处理 GET /api/v1/media/continue-watching。
func (h *MediaHandler) ContinueWatching(c *gin.Context) {
	limit, ok := parseMediaLimit(c)
	if !ok {
		return
	}
	page, err := h.service.List(c.Request.Context(), domain.MediaListRequest{
		Cursor: c.Query("cursor"), Limit: limit, ContinueWatching: true,
	}, c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	items := make([]mediaSummaryJSON, 0, len(page.Items))
	for _, item := range page.Items {
		items = append(items, presentMediaSummary(item))
	}
	var nextCursor any
	if page.NextCursor != "" {
		nextCursor = page.NextCursor
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "next_cursor": nextCursor})
}

// Get 处理 GET /api/v1/media/:id。
func (h *MediaHandler) Get(c *gin.Context) {
	item, err := h.service.Get(c.Request.Context(), c.Param("id"), c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.JSON(http.StatusOK, presentMediaDetail(item))
}

// Thumbnail 处理 GET /api/v1/media/:id/thumbnail。
func (h *MediaHandler) Thumbnail(c *gin.Context) {
	content, err := h.service.Thumbnail(c.Request.Context(), c.Param("id"), c.Query("variant"), c.GetHeader("If-None-Match"), c.GetString("user_id"))
	if err != nil {
		response.FromError(c, err)
		return
	}
	c.Header("ETag", content.ETag)
	c.Header("Cache-Control", "private, max-age=604800, must-revalidate")
	if content.NotModified {
		c.Status(http.StatusNotModified)
		return
	}
	c.Data(http.StatusOK, content.MIMEType, content.Data)
}

func presentMediaSummary(item domain.Media) mediaSummaryJSON {
	escaped := url.PathEscape(item.ID)
	summary := mediaSummaryJSON{
		ID: item.ID, Title: item.Title, Filename: item.Filename, MediaType: item.MediaType,
		LibraryKind: item.LibraryKind,
		DurationMS:  item.DurationMS, Width: item.Width, Height: item.Height,
		Favorite: item.Favorite, ProgressMS: item.ProgressMS, Completed: item.Completed,
		UserDataRevision: item.UserDataRevision, Status: item.Status,
		CreatedAt: item.DiscoveredAt.UTC().Format(time.RFC3339Nano),
	}
	if item.CatalogItemID != "" {
		value := item.CatalogItemID
		summary.CatalogItemID = &value
	}
	if item.LastPlayedAt != nil {
		value := item.LastPlayedAt.UTC().Format(time.RFC3339Nano)
		summary.LastPlayedAt = &value
	}
	if item.MediaType == domain.MediaTypeVideo {
		streamURL := "/api/v1/media/" + escaped + "/stream"
		summary.StreamURL = &streamURL
	} else if item.MediaType == domain.MediaTypeImage {
		originalURL := "/api/v1/media/" + escaped + "/original"
		summary.OriginalURL = &originalURL
	}
	if item.HasThumbnail {
		summary.ThumbnailURL = "/api/v1/media/" + escaped + "/thumbnail"
	}
	if item.HasCardThumbnail {
		summary.CardThumbnailURL = "/api/v1/media/" + escaped + "/thumbnail?variant=card"
	}
	return summary
}

func parseMediaLimit(c *gin.Context) (int, bool) {
	if raw, exists := c.GetQuery("limit"); exists {
		value, err := strconv.Atoi(raw)
		if err != nil {
			response.Error(c, http.StatusBadRequest, "INVALID_REQUEST", "limit 必须是整数", nil)
			return 0, false
		}
		return value, true
	}
	return 0, true
}

func presentMediaDetail(item domain.Media) mediaDetailJSON {
	result := mediaDetailJSON{
		mediaSummaryJSON: presentMediaSummary(item), SourceID: item.SourceID, MIMEType: item.MIMEType,
		FileSize: item.FileSize, VideoCodec: item.VideoCodec, AudioCodec: item.AudioCodec,
		Container: item.Container, Bitrate: item.Bitrate, FrameRateNum: item.FrameRateNum,
		FrameRateDen: item.FrameRateDen, AudioTrackCount: item.AudioTrackCount,
		Orientation: item.Orientation,
	}
	if item.CapturedAt != nil {
		value := item.CapturedAt.UTC().Format(time.RFC3339Nano)
		result.CapturedAt = &value
	}
	if item.IndexedAt != nil {
		value := item.IndexedAt.UTC().Format(time.RFC3339Nano)
		result.IndexedAt = &value
	}
	return result
}
