package domain

import "time"

const (
	// SourceTypeLocal 表示本地或已挂载目录，对应 sources.source_type = local。
	SourceTypeLocal = "local"

	// SourceStatusOnline 表示可正常访问，对应 sources.status = online。
	SourceStatusOnline = "online"
	// SourceStatusOffline 表示当前无法访问，对应 sources.status = offline。
	SourceStatusOffline = "offline"
	// SourceStatusDegraded 表示可访问但存在部分异常，对应 sources.status = degraded。
	SourceStatusDegraded = "degraded"
	// SourceStatusDisabled 表示用户禁用，对应 sources.status = disabled。
	SourceStatusDisabled = "disabled"
)

// Source 表示经过安全校验的媒体来源，对应 sources 表。
type Source struct {
	// ID 对应 sources.id，稳定业务主键。
	ID string
	// Name 对应 sources.name，用户可见名称。
	Name string
	// Type 对应 sources.source_type，V1 固定为 local。
	Type string
	// RootPath 对应 sources.root_path，仅服务端内部使用的真实根目录，API 响应不得返回。
	RootPath string
	// Enabled 对应 sources.enabled，是否参与默认查询与扫描。
	Enabled bool
	// Status 对应 sources.status（online/offline/degraded/disabled）。
	Status string
	// LastScanID 对应 sources.last_scan_id，最近一次完整成功扫描的任务 ID。
	LastScanID string
	// LastSeenAt 对应 sources.last_seen_at_ms，最近一次完整成功访问时间；从未成功时为 nil。
	LastSeenAt *time.Time
	// CreatedAt 对应 sources.created_at_ms。
	CreatedAt time.Time
	// UpdatedAt 对应 sources.updated_at_ms。
	UpdatedAt time.Time
}

// CreateSourceCommand 表示创建本地媒体源的业务输入（非表行，写入前经校验）。
type CreateSourceCommand struct {
	// Name 将写入 sources.name。
	Name string
	// RootPath 将写入 sources.root_path，须通过白名单校验。
	RootPath string
}

// UpdateSourceCommand 表示媒体源的部分更新输入（非表行）。
type UpdateSourceCommand struct {
	// ID 对应 sources.id，待更新媒体源。
	ID string
	// Name 非空时更新 sources.name。
	Name *string
	// RootPath 非空时重新校验并更新 sources.root_path。
	RootPath *string
	// Enabled 非空时更新 sources.enabled。
	Enabled *bool
}
