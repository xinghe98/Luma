package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// SourceRepository 使用 SQLite 实现媒体源持久化。
type SourceRepository struct {
	// db 是共享 SQLite 连接池。
	db *sql.DB
}

// NewSourceRepository 创建 SQLite 媒体源 Repository。
func NewSourceRepository(db *sql.DB) (*SourceRepository, error) {
	if db == nil {
		return nil, fmt.Errorf("数据库不能为空")
	}
	return &SourceRepository{db: db}, nil
}

// List 返回全部媒体源，并按创建时间和 ID 稳定排序。
func (r *SourceRepository) List(ctx context.Context) ([]domain.Source, error) {
	rows, err := r.db.QueryContext(ctx, `SELECT id, name, source_type, root_path, enabled, status,
        COALESCE(last_scan_id, ''), last_seen_at_ms, created_at_ms, updated_at_ms
        FROM sources WHERE deleted_at_ms IS NULL ORDER BY created_at_ms, id`)
	if err != nil {
		return nil, fmt.Errorf("查询媒体源: %w", err)
	}
	defer rows.Close()
	var sources []domain.Source
	for rows.Next() {
		source, err := scanSource(rows)
		if err != nil {
			return nil, err
		}
		sources = append(sources, source)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("遍历媒体源结果: %w", err)
	}
	return sources, nil
}

// Get 根据 ID 返回媒体源。
func (r *SourceRepository) Get(ctx context.Context, id string) (domain.Source, error) {
	row := r.db.QueryRowContext(ctx, `SELECT id, name, source_type, root_path, enabled, status,
        COALESCE(last_scan_id, ''), last_seen_at_ms, created_at_ms, updated_at_ms
        FROM sources WHERE id = ? AND deleted_at_ms IS NULL`, id)
	source, err := scanSource(row)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.Source{}, domain.ErrSourceNotFound
	}
	return source, err
}

// Create 插入一个经过业务校验的媒体源。
func (r *SourceRepository) Create(ctx context.Context, source domain.Source) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO sources(
        id, name, source_type, root_path, enabled, status, created_at_ms, updated_at_ms
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, source.ID, source.Name, source.Type,
		source.RootPath, boolInt(source.Enabled), source.Status,
		source.CreatedAt.UnixMilli(), source.UpdatedAt.UnixMilli())
	if err != nil {
		if isUniqueConstraint(err) {
			return domain.ErrSourceConflict
		}
		return fmt.Errorf("创建媒体源: %w", err)
	}
	return nil
}

// Update 保存媒体源的可修改字段。
func (r *SourceRepository) Update(ctx context.Context, source domain.Source) error {
	result, err := r.db.ExecContext(ctx, `UPDATE sources SET name = ?, root_path = ?, enabled = ?, status = ?, updated_at_ms = ?
        WHERE id = ? AND deleted_at_ms IS NULL`, source.Name, source.RootPath,
		boolInt(source.Enabled), source.Status, source.UpdatedAt.UnixMilli(), source.ID)
	if err != nil {
		if isUniqueConstraint(err) {
			return domain.ErrSourceConflict
		}
		return fmt.Errorf("更新媒体源: %w", err)
	}
	return requireAffected(result, domain.ErrSourceNotFound)
}

// SetStatus 更新媒体源在线、离线或降级状态。
func (r *SourceRepository) SetStatus(ctx context.Context, id, status string, now time.Time) error {
	result, err := r.db.ExecContext(ctx, `UPDATE sources SET status = ?, updated_at_ms = ? WHERE id = ? AND deleted_at_ms IS NULL`,
		status, now.UnixMilli(), id)
	if err != nil {
		return fmt.Errorf("更新媒体源状态: %w", err)
	}
	return requireAffected(result, domain.ErrSourceNotFound)
}

// SoftDelete 软删除媒体源，释放根路径唯一约束并保留关联索引数据。
func (r *SourceRepository) SoftDelete(ctx context.Context, id string, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	nowMS := now.UnixMilli()
	result, err := tx.ExecContext(ctx, `UPDATE sources SET enabled = 0, status = ?, deleted_at_ms = ?, updated_at_ms = ?
		WHERE id = ? AND deleted_at_ms IS NULL`, domain.SourceStatusDisabled, nowMS, nowMS, id)
	if err != nil {
		return fmt.Errorf("软删除媒体源: %w", err)
	}
	if err := requireAffected(result, domain.ErrSourceNotFound); err != nil {
		return err
	}
	// 仅取消尚未领取的任务；运行中任务由 Worker 自行收尾，避免双写终态竞态。
	_, err = tx.ExecContext(ctx, `UPDATE scan_jobs SET status = 'cancelled', phase = 'finished', finished_at_ms = ?,
		error_code = 'SOURCE_DELETED', error_message = '媒体源已删除', updated_at_ms = ?
		WHERE source_id = ? AND status = 'pending'`, nowMS, nowMS, id)
	if err != nil {
		return fmt.Errorf("取消媒体源扫描任务: %w", err)
	}
	_, err = tx.ExecContext(ctx, `UPDATE jobs SET status = 'cancelled', finished_at_ms = ?,
		error_code = 'SOURCE_DELETED', error_message = '媒体源已删除',
		locked_at_ms = NULL, locked_by = NULL, updated_at_ms = ?
		WHERE job_type = 'scan_source' AND entity_id = ? AND status = 'pending'`, nowMS, nowMS, id)
	if err != nil {
		return fmt.Errorf("取消通用扫描任务: %w", err)
	}
	_, err = tx.ExecContext(ctx, `UPDATE jobs SET status = 'cancelled', finished_at_ms = ?,
		error_code = 'SOURCE_DELETED', error_message = '媒体源已删除',
		locked_at_ms = NULL, locked_by = NULL, updated_at_ms = ?
		WHERE job_type IN ('probe_media', 'generate_thumbnail') AND status IN ('pending', 'running')
		AND entity_id IN (SELECT id FROM media_items WHERE source_id = ?)`, nowMS, nowMS, id)
	if err != nil {
		return fmt.Errorf("取消媒体处理任务: %w", err)
	}
	return tx.Commit()
}

// rowScanner 抽象 sql.Row 和 sql.Rows 的共同 Scan 能力。
type rowScanner interface {
	// Scan 将当前数据库行写入目标值。
	Scan(...any) error
}

// scanSource 将数据库行转换为领域媒体源。
func scanSource(row rowScanner) (domain.Source, error) {
	var source domain.Source
	var enabled int
	var lastSeen sql.NullInt64
	var createdMS, updatedMS int64
	err := row.Scan(&source.ID, &source.Name, &source.Type, &source.RootPath, &enabled,
		&source.Status, &source.LastScanID, &lastSeen, &createdMS, &updatedMS)
	if err != nil {
		return domain.Source{}, err
	}
	source.Enabled = enabled == 1
	source.CreatedAt = time.UnixMilli(createdMS).UTC()
	source.UpdatedAt = time.UnixMilli(updatedMS).UTC()
	if lastSeen.Valid {
		value := time.UnixMilli(lastSeen.Int64).UTC()
		source.LastSeenAt = &value
	}
	return source, nil
}

// boolInt 将布尔值转换为 SQLite 使用的 0 或 1。
func boolInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

// requireAffected 将零行更新转换为领域不存在错误。
func requireAffected(result sql.Result, notFound error) error {
	count, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if count == 0 {
		return notFound
	}
	return nil
}

// isUniqueConstraint 判断 SQLite 错误是否由唯一约束触发。
func isUniqueConstraint(err error) bool {
	return strings.Contains(strings.ToLower(err.Error()), "unique constraint")
}

// isForeignKeyConstraint 判断 SQLite 错误是否由外键约束触发。
func isForeignKeyConstraint(err error) bool {
	return strings.Contains(strings.ToLower(err.Error()), "foreign key constraint")
}
