package sqlite

import (
	"database/sql"
	"fmt"
)

// ScanRepository 使用 SQLite 实现扫描任务调度和媒体索引协调。
type ScanRepository struct {
	// db 是共享 SQLite 连接池。
	db *sql.DB
}

// NewScanRepository 创建 SQLite 扫描 Repository。
func NewScanRepository(db *sql.DB) (*ScanRepository, error) {
	if db == nil {
		return nil, fmt.Errorf("数据库不能为空")
	}
	return &ScanRepository{db: db}, nil
}
