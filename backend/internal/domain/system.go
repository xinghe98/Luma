package domain

// Health 表示无需认证即可返回的进程存活信息。
type Health struct {
	// Status 是服务存活状态。
	Status string
	// Version 是当前服务版本。
	Version string
}

// SystemInfo 表示认证后可查询的服务端运行信息。
type SystemInfo struct {
	// Version 是当前服务版本。
	Version string
	// Platform 是服务端操作系统名称。
	Platform string
	// Architecture 是服务端处理器架构。
	Architecture string
	// Database 是数据库连接状态。
	Database string
}
