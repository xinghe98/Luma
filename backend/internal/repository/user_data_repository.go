package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// UserDataRepository 定义用户媒体数据与标签关系的原子持久化能力。
type UserDataRepository interface {
	Get(context.Context, string, string) (domain.MediaUserData, error)
	Update(context.Context, domain.UpdateUserDataCommand, time.Time) (domain.MediaUserData, error)
	UpdateProgress(context.Context, domain.UpdateProgressCommand) (domain.MediaUserData, error)
}
