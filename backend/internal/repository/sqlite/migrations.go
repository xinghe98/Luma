package sqlite

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
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
	// checksum 是首次发布时固定的 SQL SHA-256，防止历史迁移被改写。
	checksum string
}

// allMigrations 按版本顺序保存当前服务端支持的全部迁移。
var allMigrations = []migration{
	{version: 1, name: "001_initial", sql: migrations.Initial, checksum: "66a24775d3d3661bfcd177cb718b191f3b8f0255ba714050ad5eb7381d3514c2"},
	{version: 2, name: "002_stage2_scan", sql: migrations.Stage2Scan, checksum: "c66d5301004368535ca6393e123a85d137024c85f6ed51e811a0b395663d588d"},
	{version: 3, name: "003_jobs_interrupted", sql: migrations.JobsInterrupted, checksum: "307973a16360ab572b07c24ad3fc9711fb673806a54cdef1229deefecd9b1fe0"},
	{version: 4, name: "004_stage3_processing", sql: migrations.Stage3Processing, checksum: "846dc63f8776f1e9da5eef3fe3e4c26b5aa8f35d662868ef0ab6b1a1e08f1240"},
	{version: 5, name: "005_stage4_media_api", sql: migrations.Stage4MediaAPI, checksum: "282eb6f2d6ce1d5f3392078930c7f79706e5f4486297b23c8fe4dc74587c65f7"},
	{version: 6, name: "006_media_asset_content_hash", sql: migrations.MediaAssetContentHash, checksum: "0d33f2811f909036c0205d2fa0c04ea12f6e4cb6a8273040b9a5aa8287e4e053"},
	{version: 7, name: "007_stage6_user_data", sql: migrations.Stage6UserData, checksum: "c9002e3fbd502dd85aa0db7deeb51c08d4be25eb0fcb5fb25814b31899c0b431"},
	{version: 8, name: "008_card_thumbnail_jobs", sql: migrations.CardThumbnailJobs, checksum: "7904535b52d7fa4581f8cd2dfe78a1ea5f9f4ff1bdb180cef0ae10e528d5967b"},
	{version: 9, name: "009_catalog", sql: migrations.Catalog, checksum: "3c4713bcd8a3f90200580372cc613289a2cbcd15d8e5ba454e91c39fe4824888"},
	{version: 10, name: "010_access_control", sql: migrations.AccessControl, checksum: "aec68ca82d5edfd133f790327056e174dfc02bc5e07c07cd6550904d1e1247df"},
	{version: 11, name: "011_image_library", sql: migrations.ImageLibrary, checksum: "d4772da5b2160f0957bce0ce53dba0497c4fd5166dbc6b68dab5650109b75c8e"},
	{version: 12, name: "012_access_idempotency", sql: migrations.AccessIdempotency, checksum: "20450b0ea2d02b072228adf5eba058c6fce7b29466c1884daabafb2a1071e2e3"},
	{version: 13, name: "013_catalog_metadata", sql: migrations.CatalogMetadata, checksum: "69b311822b4b5b975c6f85cda8a4aad19a22bde74ac1d01b5e3b9599c27355d5"},
	{version: 14, name: "014_catalog_detail", sql: migrations.CatalogDetail, checksum: "b7d1913c804cd75c3920c5473a9c80a071cc2fe5f6859672e891123fabda04ab"},
	{version: 15, name: "015_account_sessions", sql: migrations.AccountSessions, checksum: "48d0faa5c2a1043b588cec532b33b93a77cb3da47670831c73d325fc15139f59"},
	{version: 16, name: "016_scan_metadata_runs", sql: migrations.ScanMetadataRuns, checksum: "70a6c0c693911e949bd047bda2654afcc901254ec28622e49afeedbbe4aabedd"},
	{version: 17, name: "017_sessions", sql: migrations.Sessions, checksum: "55d65235ae1e83364d2810734a445941105e638f2cd18fd4f88738987a8a197c"},
	{version: 18, name: "018_permanent_sessions", sql: migrations.PermanentSessions, checksum: "56340b39dfa6bbbc9d406844a9832319517be94ca355374586c78e55013ab1f6"},
	{version: 19, name: "019_session_device_key", sql: migrations.SessionDeviceKey, checksum: "a1cda0553119b372611ad0f1c5eae0298d3235d03abe3ce957bead04a4187bb5"},
	{version: 20, name: "020_expire_permanent_sessions", sql: migrations.ExpirePermanentSessions, checksum: "09c281670b1855f5122d0f3f3996d2d00ea648b6ceadbbcfea221c3bdf201a77"},
}

// migrate 校验已发布迁移，在单个事务中幂等升级数据库并确保默认用户存在。
// SQL 清单或数据库记录不一致时会拒绝启动，旧迁移表则在事务内补齐 checksum。
func migrate(ctx context.Context, db *sql.DB, now time.Time) error {
	if err := validateMigrationDefinitions(); err != nil {
		return err
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin database migration: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
        -- 已应用的迁移版本号。
        version INTEGER PRIMARY KEY,
        -- 迁移应用时间戳（毫秒）。
        applied_at_ms INTEGER NOT NULL,
        -- 首次发布 SQL 的 SHA-256。
        checksum TEXT NOT NULL
    )`); err != nil {
		return fmt.Errorf("create migration table: %w", err)
	}
	legacyTable, err := ensureMigrationChecksumColumn(ctx, tx)
	if err != nil {
		return err
	}
	applied, err := validateAppliedMigrations(ctx, tx, legacyTable)
	if err != nil {
		return err
	}
	nowMS := now.UnixMilli()
	for _, item := range allMigrations {
		if applied[item.version] {
			continue
		}
		if _, err := tx.ExecContext(ctx, item.sql); err != nil {
			return fmt.Errorf("apply migration %s: %w", item.name, err)
		}
		if _, err := tx.ExecContext(ctx, "INSERT INTO schema_migrations(version, applied_at_ms, checksum) VALUES (?, ?, ?)", item.version, nowMS, item.checksum); err != nil {
			return fmt.Errorf("record migration %s: %w", item.name, err)
		}
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO users(id, name, role, enabled, created_at_ms, updated_at_ms)
		VALUES ('user_local', 'Local User', 'admin', 1, ?, ?)
		ON CONFLICT(id) DO NOTHING`, nowMS, nowMS); err != nil {
		return fmt.Errorf("ensure default user: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit database migration: %w", err)
	}
	return nil
}

// validateMigrationDefinitions 确保嵌入 SQL 与首次发布清单一致，并检查版本连续性。
func validateMigrationDefinitions() error {
	for index, item := range allMigrations {
		if item.version != index+1 {
			return fmt.Errorf("migration %s has non-contiguous version %d", item.name, item.version)
		}
		digest := sha256.Sum256([]byte(item.sql))
		if actual := hex.EncodeToString(digest[:]); actual != item.checksum {
			return fmt.Errorf("migration %s SQL checksum mismatch: got %s, want %s", item.name, actual, item.checksum)
		}
	}
	return nil
}

// ensureMigrationChecksumColumn 兼容仅含 version 与 applied_at_ms 的旧迁移表。
func ensureMigrationChecksumColumn(ctx context.Context, tx *sql.Tx) (bool, error) {
	rows, err := tx.QueryContext(ctx, `PRAGMA table_info(schema_migrations)`)
	if err != nil {
		return false, fmt.Errorf("inspect migration table: %w", err)
	}
	found := false
	for rows.Next() {
		var cid, notNull, primaryKey int
		var name, columnType string
		var defaultValue any
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultValue, &primaryKey); err != nil {
			rows.Close()
			return false, fmt.Errorf("inspect migration column: %w", err)
		}
		found = found || name == "checksum"
	}
	if err := rows.Close(); err != nil {
		return false, fmt.Errorf("close migration columns: %w", err)
	}
	if found {
		return false, nil
	}
	if _, err := tx.ExecContext(ctx, `ALTER TABLE schema_migrations ADD COLUMN checksum TEXT`); err != nil {
		return false, fmt.Errorf("add migration checksum: %w", err)
	}
	return true, nil
}

// validateAppliedMigrations 校验数据库记录，并只为无法保存校验值的旧库回填当前发布值。
func validateAppliedMigrations(ctx context.Context, tx *sql.Tx, allowBackfill bool) (map[int]bool, error) {
	known := make(map[int]migration, len(allMigrations))
	for _, item := range allMigrations {
		known[item.version] = item
	}
	rows, err := tx.QueryContext(ctx, `SELECT version, checksum FROM schema_migrations ORDER BY version`)
	if err != nil {
		return nil, fmt.Errorf("read applied migrations: %w", err)
	}
	type record struct {
		version  int
		checksum sql.NullString
	}
	var records []record
	for rows.Next() {
		var value record
		if err := rows.Scan(&value.version, &value.checksum); err != nil {
			rows.Close()
			return nil, fmt.Errorf("read applied migration: %w", err)
		}
		records = append(records, value)
	}
	if err := rows.Close(); err != nil {
		return nil, fmt.Errorf("close applied migrations: %w", err)
	}
	applied := make(map[int]bool, len(records))
	for _, record := range records {
		item, ok := known[record.version]
		if !ok {
			return nil, fmt.Errorf("database migration version %d is newer than this server", record.version)
		}
		if record.checksum.Valid && record.checksum.String != "" && record.checksum.String != item.checksum {
			return nil, fmt.Errorf("database migration %s checksum mismatch: got %s, want %s", item.name, record.checksum.String, item.checksum)
		}
		if !record.checksum.Valid || record.checksum.String == "" {
			if !allowBackfill {
				return nil, fmt.Errorf("database migration %s checksum is missing", item.name)
			}
			if _, err := tx.ExecContext(ctx, `UPDATE schema_migrations SET checksum=? WHERE version=?`, item.checksum, item.version); err != nil {
				return nil, fmt.Errorf("backfill migration %s checksum: %w", item.name, err)
			}
		}
		applied[item.version] = true
	}
	return applied, nil
}
