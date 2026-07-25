package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/repository"
)

// MediaService 实现媒体查询、稳定分页和缩略图读取业务。
type MediaService struct {
	// repository 提供媒体及缩略图元数据查询。
	repository repository.MediaRepository
	// thumbnails 提供缩略图内容读取能力。
	thumbnails ThumbnailReader
}

// NewMediaService 创建媒体查询服务。
func NewMediaService(repository repository.MediaRepository, thumbnails ThumbnailReader) (*MediaService, error) {
	if repository == nil || thumbnails == nil {
		return nil, errors.New("媒体 Repository 和缩略图存储不能为空")
	}
	return &MediaService{repository: repository, thumbnails: thumbnails}, nil
}

// List 校验参数并返回一页媒体。
func (s *MediaService) List(ctx context.Context, request domain.MediaListRequest, userID string) (domain.MediaPage, error) {
	query, err := normalizeMediaQuery(request, userID)
	if err != nil {
		return domain.MediaPage{}, err
	}
	if request.Cursor != "" {
		query.After, err = decodeMediaCursor(request.Cursor, query)
		if err != nil {
			return domain.MediaPage{}, err
		}
	}
	pageLimit := query.Limit
	query.Limit++
	items, err := s.repository.List(ctx, query)
	if err != nil {
		return domain.MediaPage{}, err
	}
	result := domain.MediaPage{Items: items}
	if len(items) > pageLimit {
		result.Items = items[:pageLimit]
		result.NextCursor, err = encodeMediaCursor(query, result.Items[len(result.Items)-1])
		if err != nil {
			return domain.MediaPage{}, fmt.Errorf("生成媒体 cursor: %w", err)
		}
	}
	return result, nil
}

func (s *MediaService) Count(ctx context.Context, request domain.MediaListRequest, userID string) (int, error) {
	query, err := normalizeMediaQuery(request, userID)
	if err != nil {
		return 0, err
	}
	query.After = nil
	return s.repository.Count(ctx, query)
}

// Get 返回可见媒体详情。
func (s *MediaService) Get(ctx context.Context, id, userID string) (domain.Media, error) {
	if strings.TrimSpace(id) == "" || userID == "" {
		return domain.Media{}, fmt.Errorf("%w: 媒体 ID 无效", domain.ErrInvalidRequest)
	}
	return s.repository.Get(ctx, id, userID)
}

// Thumbnail 返回默认缩略图内容或 304 短路径结果。
func (s *MediaService) Thumbnail(ctx context.Context, id, variant, ifNoneMatch, userID string) (domain.ThumbnailContent, error) {
	if strings.TrimSpace(id) == "" || strings.TrimSpace(userID) == "" {
		return domain.ThumbnailContent{}, fmt.Errorf("%w: 媒体 ID 无效", domain.ErrInvalidRequest)
	}
	if variant == "" {
		variant = domain.ThumbnailVariantDefault
	}
	if variant != domain.ThumbnailVariantDefault && variant != domain.ThumbnailVariantCard {
		return domain.ThumbnailContent{}, fmt.Errorf("%w: variant 必须是 default 或 card", domain.ErrInvalidRequest)
	}
	asset, err := s.repository.GetThumbnail(ctx, id, variant, userID)
	if err != nil {
		return domain.ThumbnailContent{}, err
	}
	etag := strongETag(asset.ContentSHA256)
	if etag != "" && etagMatches(ifNoneMatch, etag) {
		return domain.ThumbnailContent{MIMEType: asset.MIMEType, ETag: etag, NotModified: true}, nil
	}
	data, err := s.thumbnails.Read(asset.StorageKey)
	if err != nil {
		return domain.ThumbnailContent{}, err
	}
	mimeType := asset.MIMEType
	if !strings.HasPrefix(mimeType, "image/") {
		mimeType = http.DetectContentType(data)
	}
	if etag == "" {
		sum := sha256.Sum256(data)
		etag = strongETag(hex.EncodeToString(sum[:]))
		if etagMatches(ifNoneMatch, etag) {
			return domain.ThumbnailContent{MIMEType: mimeType, ETag: etag, NotModified: true}, nil
		}
	}
	return domain.ThumbnailContent{Data: data, MIMEType: mimeType, ETag: etag}, nil
}

func strongETag(contentSHA256 string) string {
	if contentSHA256 == "" {
		return ""
	}
	return `"` + contentSHA256 + `"`
}

func etagMatches(header, etag string) bool {
	for _, candidate := range strings.Split(header, ",") {
		candidate = strings.TrimSpace(candidate)
		candidate = strings.TrimPrefix(candidate, "W/")
		if candidate == "*" || candidate == etag {
			return true
		}
	}
	return false
}

func normalizeMediaQuery(request domain.MediaListRequest, userID string) (domain.MediaListQuery, error) {
	query := domain.MediaListQuery{
		UserID: userID, Search: strings.TrimSpace(request.Query), MediaType: strings.TrimSpace(request.MediaType),
		LibraryKind: strings.TrimSpace(request.LibraryKind),
		Favorite:    request.Favorite, TagID: strings.TrimSpace(request.TagID), WatchStatus: strings.TrimSpace(request.WatchStatus),
		ContinueWatching: request.ContinueWatching,
		Sort:             strings.TrimSpace(request.Sort), Order: strings.TrimSpace(request.Order), Limit: request.Limit,
	}
	if userID == "" {
		return query, fmt.Errorf("%w: 用户身份无效", domain.ErrInvalidRequest)
	}
	if len([]rune(query.Search)) > 200 {
		return query, fmt.Errorf("%w: q 最多 200 个字符", domain.ErrInvalidRequest)
	}
	if query.MediaType != "" && query.MediaType != domain.MediaTypeVideo && query.MediaType != domain.MediaTypeImage {
		return query, fmt.Errorf("%w: type 必须是 video 或 image", domain.ErrInvalidRequest)
	}
	switch query.LibraryKind {
	case "", domain.LibraryKindPersonal, domain.LibraryKindMovies, domain.LibraryKindTV:
	default:
		return query, fmt.Errorf("%w: library_kind 必须是 personal、movies 或 tv", domain.ErrInvalidRequest)
	}
	if len(query.TagID) > 200 {
		return query, fmt.Errorf("%w: tag_id 无效", domain.ErrInvalidRequest)
	}
	switch query.WatchStatus {
	case "", domain.WatchStatusUnwatched, domain.WatchStatusWatching, domain.WatchStatusCompleted:
	default:
		return query, fmt.Errorf("%w: watch_status 必须是 unwatched、watching 或 completed", domain.ErrInvalidRequest)
	}
	if query.ContinueWatching {
		if query.MediaType != "" && query.MediaType != domain.MediaTypeVideo {
			return query, fmt.Errorf("%w: 继续观看只支持视频", domain.ErrInvalidRequest)
		}
		query.MediaType = domain.MediaTypeVideo
		query.Sort = domain.MediaSortLastPlayedAt
		query.Order = domain.SortDescending
	}
	if query.Sort == "" {
		query.Sort = domain.MediaSortCreatedAt
	}
	switch query.Sort {
	case domain.MediaSortCreatedAt, domain.MediaSortFilename, domain.MediaSortDuration, domain.MediaSortFileSize:
	case domain.MediaSortLastPlayedAt:
		if !query.ContinueWatching {
			return query, fmt.Errorf("%w: sort 无效", domain.ErrInvalidRequest)
		}
	default:
		return query, fmt.Errorf("%w: sort 无效", domain.ErrInvalidRequest)
	}
	if query.Order == "" {
		query.Order = domain.SortDescending
	}
	if query.Order != domain.SortAscending && query.Order != domain.SortDescending {
		return query, fmt.Errorf("%w: order 必须是 asc 或 desc", domain.ErrInvalidRequest)
	}
	if query.Limit == 0 {
		query.Limit = 50
	}
	if query.Limit < 1 || query.Limit > 100 {
		return query, fmt.Errorf("%w: limit 必须在 1 到 100 之间", domain.ErrInvalidRequest)
	}
	return query, nil
}
