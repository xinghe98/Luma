// 本文件提供来源根目录变更所需的只读索引检查，直接协作 SQLite 连接且不持有额外生命周期资源。
package app

import (
	"context"
	"database/sql"
	"fmt"
)

// sourceIndexedMediaChecker 查询来源是否已产生媒体索引，避免旧媒体 ID 被新根目录复用。
type sourceIndexedMediaChecker struct {
	db *sql.DB
}

// HasIndexedMedia 返回来源是否存在任意媒体记录；查询失败时禁止继续变更根目录。
func (c sourceIndexedMediaChecker) HasIndexedMedia(ctx context.Context, sourceID string) (bool, error) {
	var exists bool
	if err := c.db.QueryRowContext(ctx,
		`SELECT EXISTS(SELECT 1 FROM media_items WHERE source_id = ?)`, sourceID).Scan(&exists); err != nil {
		return false, fmt.Errorf("检查媒体源索引: %w", err)
	}
	return exists, nil
}
