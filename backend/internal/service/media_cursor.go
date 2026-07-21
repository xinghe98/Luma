package service

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

type mediaCursor struct {
	// Version 是游标格式版本。
	Version int `json:"v"`
	// Sort 是游标对应的排序字段。
	Sort string `json:"sort"`
	// Order 是游标对应的排序方向。
	Order string `json:"order"`
	// StringValue 是字符串排序键值。
	StringValue string `json:"string_value,omitempty"`
	// IntValue 是整数排序键值。
	IntValue int64 `json:"int_value,omitempty"`
	// Null 表示排序键是否为空。
	Null bool `json:"null,omitempty"`
	// ID 是用于稳定排序的媒体标识。
	ID string `json:"id"`
	// FilterHash 是查询筛选条件摘要。
	FilterHash string `json:"filter_hash"`
}

func encodeMediaCursor(query domain.MediaListQuery, item domain.Media) (string, error) {
	payload := mediaCursor{Version: 3, Sort: query.Sort, Order: query.Order, ID: item.ID, FilterHash: mediaFilterHash(query)}
	switch query.Sort {
	case domain.MediaSortFilename:
		payload.StringValue = item.Filename
	case domain.MediaSortDuration:
		payload.Null = item.DurationMS == nil
		if item.DurationMS != nil {
			payload.IntValue = *item.DurationMS
		}
	case domain.MediaSortFileSize:
		payload.IntValue = item.FileSize
	case domain.MediaSortLastPlayedAt:
		if item.LastPlayedAt == nil {
			return "", fmt.Errorf("继续观看媒体缺少最近播放时间")
		}
		payload.IntValue = item.LastPlayedAt.UnixMilli()
	default:
		payload.IntValue = item.DiscoveredAt.UnixMilli()
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(encoded), nil
}

func decodeMediaCursor(value string, query domain.MediaListQuery) (*domain.MediaPageKey, error) {
	decoded, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil {
		return nil, fmt.Errorf("%w: cursor 格式无效", domain.ErrInvalidRequest)
	}
	var payload mediaCursor
	if err := json.Unmarshal(decoded, &payload); err != nil {
		return nil, fmt.Errorf("%w: cursor 格式无效", domain.ErrInvalidRequest)
	}
	if payload.Version != 3 || payload.ID == "" || payload.Sort != query.Sort || payload.Order != query.Order || payload.FilterHash != mediaFilterHash(query) {
		return nil, fmt.Errorf("%w: cursor 与当前查询不匹配", domain.ErrInvalidRequest)
	}
	return &domain.MediaPageKey{StringValue: payload.StringValue, IntValue: payload.IntValue, Null: payload.Null, ID: payload.ID}, nil
}

func mediaFilterHash(query domain.MediaListQuery) string {
	value, _ := json.Marshal(struct {
		UserID string `json:"user_id"`
		// Search 是文件名搜索词。
		Search string `json:"search"`
		// MediaType 是媒体类型筛选值。
		MediaType        string `json:"media_type"`
		Favorite         *bool  `json:"favorite"`
		TagID            string `json:"tag_id"`
		WatchStatus      string `json:"watch_status"`
		ContinueWatching bool   `json:"continue_watching"`
		// Sort 是排序字段。
		Sort string `json:"sort"`
		// Order 是排序方向。
		Order string `json:"order"`
	}{query.UserID, query.Search, query.MediaType, query.Favorite, query.TagID, query.WatchStatus, query.ContinueWatching, query.Sort, query.Order})
	sum := sha256.Sum256(value)
	return hex.EncodeToString(sum[:])
}
