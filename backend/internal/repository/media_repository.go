package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// MediaRepository 定义媒体查询 API 所需的只读持久化能力。
type MediaRepository interface {
	List(context.Context, domain.MediaListQuery) ([]domain.Media, error)
	Count(context.Context, domain.MediaListQuery) (int, error)
	Get(context.Context, string, string) (domain.Media, error)
	GetThumbnail(context.Context, string, string, string) (domain.ThumbnailAsset, error)
	// GetImageDeleteTarget 返回授权可见的图片删除定位；非图片媒体返回 ErrInvalidRequest。
	GetImageDeleteTarget(context.Context, string, string) (domain.DeleteImageTarget, error)
	// DeleteImageRecord 在文件删除后原子删除媒体行、级联清理、写墓碑并清除处理任务。
	DeleteImageRecord(context.Context, domain.DeleteImageTarget, time.Time) error
}
