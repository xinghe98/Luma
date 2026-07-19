package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// TagRepository 定义用户私有标签的持久化能力。
type TagRepository interface {
	List(context.Context, string) ([]domain.Tag, error)
	Create(context.Context, domain.Tag) error
	Update(context.Context, domain.Tag, int64) (domain.Tag, error)
	Delete(context.Context, string, string, time.Time) error
}
