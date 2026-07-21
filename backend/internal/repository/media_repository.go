package repository

import (
	"context"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// MediaRepository 定义媒体查询 API 所需的只读持久化能力。
type MediaRepository interface {
	List(context.Context, domain.MediaListQuery) ([]domain.Media, error)
	Get(context.Context, string, string) (domain.Media, error)
	GetThumbnail(context.Context, string, string) (domain.ThumbnailAsset, error)
}
