package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/migrations"
)

// migration 表示一个按版本顺序执行的嵌入式数据库迁移。
type migration struct {
	// version 是单调递增的迁移版本号。
	version int
	// name 是错误信息使用的迁移名称。
	name string
	// sql 是需要在事务内执行的 SQL 文本。
	sql string
}

// allMigrations 按版本顺序保存当前服务端支持的全部迁移。
var allMigrations = []migration{
	{version: 1, name: "001_initial", sql: migrations.Initial},
	{version: 2, name: "002_stage2_scan", sql: migrations.Stage2Scan},
	{version: 3, name: "003_jobs_interrupted", sql: migrations.JobsInterrupted},
	{version: 4, name: "004_stage3_processing", sql: migrations.Stage3Processing},
	{version: 5, name: "005_stage4_media_api", sql: migrations.Stage4MediaAPI},
	{version: 6, name: "006_media_asset_content_hash", sql: migrations.MediaAssetContentHash},
	{version: 7, name: "007_stage6_user_data", sql: migrations.Stage6UserData},
	{version: 8, name: "008_card_thumbnail_jobs", sql: migrations.CardThumbnailJobs},
}

// migrate 在单个事务中幂等应用数据库迁移并确保默认用户存在。
func migrate(ctx context.Context, db *sql.DB, now time.Time) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin database migration: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
        -- 已应用的迁移版本号。
        version INTEGER PRIMARY KEY,
        -- 迁移应用时间戳（毫秒）。
        applied_at_ms INTEGER NOT NULL
    )`); err != nil {
		return fmt.Errorf("create migration table: %w", err)
	}
	nowMS := now.UnixMilli()
	for _, item := range allMigrations {
		var applied int
		if err := tx.QueryRowContext(ctx, "SELECT COUNT(*) FROM schema_migrations WHERE version = ?", item.version).Scan(&applied); err != nil {
			return fmt.Errorf("read migration version %d: %w", item.version, err)
		}
		if applied != 0 {
			continue
		}
		if _, err := tx.ExecContext(ctx, item.sql); err != nil {
			return fmt.Errorf("apply migration %s: %w", item.name, err)
		}
		if _, err := tx.ExecContext(ctx, "INSERT INTO schema_migrations(version, applied_at_ms) VALUES (?, ?)", item.version, nowMS); err != nil {
			return fmt.Errorf("record migration %s: %w", item.name, err)
		}
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO users(id, name, created_at_ms, updated_at_ms)
        VALUES ('user_local', 'Local User', ?, ?)
        ON CONFLICT(id) DO NOTHING`, nowMS, nowMS); err != nil {
		return fmt.Errorf("ensure default user: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit database migration: %w", err)
	}
	return nil
}
