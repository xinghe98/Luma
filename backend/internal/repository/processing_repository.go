package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// ProcessingRepository 持久化媒体探测与缩略图任务及其状态变更。
type ProcessingRepository interface {
	// EnqueueProbe 幂等创建最多执行两次的媒体探测任务。
	EnqueueProbe(context.Context, string, string, time.Time) error
	// EnqueueThumbnail 确保默认缩略图资产存在并幂等创建缩略图任务。
	EnqueueThumbnail(context.Context, string, string, string, string, time.Time) error
	// Claim 原子领取指定类型任务并递增执行次数。
	Claim(context.Context, string, string, time.Time) (domain.ProcessingJob, error)
	// GetMedia 返回有效媒体源中的内部文件定位和当前版本。
	GetMedia(context.Context, string) (domain.MediaInput, error)
	// CompleteProbe 在文件版本匹配时提交元数据并投递缩略图任务。
	CompleteProbe(context.Context, domain.ProcessingJob, domain.MediaInput, domain.ProbeResult, string, string, string, time.Time) (bool, error)
	// CompleteThumbnail 在文件版本匹配时提交资产并将媒体标记为 ready。
	CompleteThumbnail(context.Context, domain.ProcessingJob, domain.MediaInput, domain.ThumbnailResult, time.Time) (bool, error)
	// Fail 记录安全错误信息，并返回任务是否会再次执行。
	Fail(context.Context, domain.ProcessingJob, string, string, time.Time) (bool, error)
	// Recover 恢复服务异常退出时遗留的全部运行中任务。
	Recover(context.Context, time.Time) error
	// ReclaimExpired 回收锁持有时间超过阈值的运行中任务。
	ReclaimExpired(context.Context, time.Time, time.Duration) error
	// ListOrphans 返回处于处理状态但没有活跃任务的媒体。
	ListOrphans(context.Context, string, int) ([]domain.MediaInput, error)
}
