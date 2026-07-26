package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// SourceRepository 定义媒体源业务所需的持久化能力。
type SourceRepository interface {
	// List 返回全部未硬删除的媒体源，包括已禁用来源。
	List(context.Context) ([]domain.Source, error)
	// Get 根据稳定标识读取媒体源。
	Get(context.Context, string) (domain.Source, error)
	// Create 创建本地媒体源。
	Create(context.Context, domain.Source) error
	// Update 更新媒体源名称、根目录和启用状态。
	Update(context.Context, domain.Source) error
	// SetStatus 更新媒体源运行状态。
	SetStatus(context.Context, string, string, time.Time) error
	// SoftDelete 删除媒体源；未初始化来源会硬删除，已有扫描或媒体记录时软删除并保留索引与用户数据。
	SoftDelete(context.Context, string, time.Time) error
}
