package domain

import "time"

const (
	// ScanStatusPending 表示扫描任务等待 Worker 领取，对应 scan_jobs/jobs.status = pending。
	ScanStatusPending = "pending"
	// ScanStatusRunning 表示正在遍历媒体源，对应 scan_jobs/jobs.status = running。
	ScanStatusRunning = "running"
	// ScanStatusCompleted 表示完整成功并已提交 missing，对应 scan_jobs/jobs.status = completed。
	ScanStatusCompleted = "completed"
	// ScanStatusFailed 表示因错误结束且未提交 missing，对应 scan_jobs.status = failed。
	ScanStatusFailed = "failed"
	// ScanStatusCancelled 表示被用户取消，对应 scan_jobs.status = cancelled。
	ScanStatusCancelled = "cancelled"
	// ScanStatusInterrupted 表示服务退出导致中断，对应 scan_jobs.status = interrupted。
	ScanStatusInterrupted = "interrupted"
)

// ScanJob 表示持久化媒体源扫描任务及其进度，对应 scan_jobs（及关联 jobs）行。
type ScanJob struct {
	// ID 对应 scan_jobs.id / jobs.id，同时作为本次扫描的 scan_id 写入 media_items.last_seen_scan_id。
	ID string
	// SourceID 对应 scan_jobs.source_id / jobs.entity_id，待扫描媒体源。
	SourceID string
	// Status 对应 scan_jobs.status（pending/running/completed/failed/cancelled/interrupted）。
	Status string
	// Phase 对应 scan_jobs.phase，如 queued、walking、completed、finished。
	Phase string
	// DiscoveredCount 对应 scan_jobs.discovered_count，已发现的受支持媒体文件数。
	DiscoveredCount int64
	// ProcessedCount 对应 scan_jobs.processed_count，已成功写入索引的媒体文件数。
	ProcessedCount int64
	// FailedCount 对应 scan_jobs.failed_count，单文件处理失败数。
	FailedCount int64
	// StartedAt 对应 scan_jobs.started_at_ms，Worker 开始执行时间；未开始时为 nil。
	StartedAt *time.Time
	// FinishedAt 对应 scan_jobs.finished_at_ms，进入终态的时间；进行中为 nil。
	FinishedAt *time.Time
	// ErrorCode 对应 scan_jobs.error_code，稳定失败/中断错误码。
	ErrorCode string
	// ErrorMessage 对应 scan_jobs.error_message，诊断说明（不含真实绝对路径）。
	ErrorMessage string
	// CreatedAt 对应 scan_jobs.created_at_ms，任务创建时间。
	CreatedAt time.Time
	// UpdatedAt 对应 scan_jobs.updated_at_ms，任务最后更新时间。
	UpdatedAt time.Time
	// Processing 非表字段：按 last_seen_scan_id = 本任务 汇总的媒体处理进度。
	Processing ProcessingSummary
}

// ProcessingSummary 汇总一次扫描关联媒体的 ffprobe/缩略图状态（由 media_items 聚合，非独立表）。
type ProcessingSummary struct {
	// Status 汇总态：pending、running、completed 或 completed_with_errors。
	Status string
	// Total 本次扫描最后确认存在的媒体总数（last_seen_scan_id = 本 scan_id）。
	Total int64
	// Discovered 仍为 discovered 状态的媒体数。
	Discovered int64
	// Probing 仍为 probing 状态的媒体数。
	Probing int64
	// Thumbnailing 仍为 thumbnailing 状态的媒体数。
	Thumbnailing int64
	// Ready 已 ready 的媒体数。
	Ready int64
	// Failed 最终 failed 的媒体数。
	Failed int64
}
