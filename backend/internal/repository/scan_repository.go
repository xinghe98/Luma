package repository

import (
	"context"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// ScanRepository 定义扫描任务和媒体索引协调所需的持久化能力。
type ScanRepository interface {
	// CreateJob 原子创建通用任务和扫描任务记录。
	CreateJob(context.Context, domain.ScanJob) error
	// GetJob 根据任务标识读取扫描任务。
	GetJob(context.Context, string) (domain.ScanJob, error)
	// LatestJob 返回指定媒体源或全局最近的扫描任务。
	LatestJob(context.Context, string) (domain.ScanJob, error)
	// ClaimNextJob 原子领取一个待执行扫描任务。
	ClaimNextJob(context.Context, string, time.Time) (domain.ScanJob, error)
	// NeedsQuickHash 判断当前文件是否需要计算快速指纹才能完成身份匹配。
	NeedsQuickHash(context.Context, string, domain.DiscoveredFile) (bool, error)
	// ReconcileFile 按路径、文件 ID、快速指纹的优先级写入媒体索引。
	ReconcileFile(context.Context, string, string, string, domain.DiscoveredFile, time.Time) (domain.ReconcileResult, error)
	// ReconcileSidecar indexes a read-only NFO without creating media processing work.
	ReconcileSidecar(context.Context, string, string, domain.DiscoveredFile, time.Time) error
	// AddProgress 原子增加扫描任务统计计数。
	AddProgress(context.Context, string, int64, int64, int64, time.Time) error
	// MarkFileFailed 记录单文件失败并保留同路径索引的 last_seen，避免误标 missing。
	MarkFileFailed(context.Context, string, string, domain.DiscoveredFile, time.Time) error
	// HasActiveJob 判断媒体源是否存在 pending/running 扫描任务。
	HasActiveJob(context.Context, string) (bool, error)
	// CompleteJob 原子标记 missing 并提交扫描任务完成状态。
	CompleteJob(context.Context, string, string, time.Time) error
	// FinishJobWithoutCommit 将任务置为失败、中断或取消，且绝不标记 missing。
	FinishJobWithoutCommit(context.Context, string, string, string, string, time.Time) error
	// InterruptRunningJobs 在服务启动时恢复上次异常退出遗留的扫描任务。
	InterruptRunningJobs(context.Context, time.Time) error
}
