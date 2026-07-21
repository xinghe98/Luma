package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// Fail 重试尚未耗尽的任务；最终失败时同步媒体及缩略图资产。
func (r *ProcessingRepository) Fail(ctx context.Context, job domain.ProcessingJob, code, message string, now time.Time) (bool, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	retry := job.Attempt < job.MaxAttempts
	status, available, finished := "failed", now.UnixMilli(), any(now.UnixMilli())
	if retry {
		status, available, finished = "pending", now.Add(time.Second).UnixMilli(), nil
	}
	result, err := tx.ExecContext(ctx, `UPDATE jobs SET status = ?, available_at_ms = ?, finished_at_ms = ?,
        locked_at_ms = NULL, locked_by = NULL, error_code = ?, error_message = ?, updated_at_ms = ?
        WHERE id = ? AND job_type = ? AND entity_id = ? AND status = 'running'
        AND locked_by = ? AND attempt_count = ?`,
		status, available, finished, nullableText(code), nullableText(message), now.UnixMilli(), job.ID, job.Type, job.MediaID, job.WorkerID, job.Attempt)
	if err != nil {
		return false, fmt.Errorf("记录媒体任务失败: %w", err)
	}
	if err := requireAffected(result, domain.ErrNoPendingJob); err != nil {
		return false, err
	}
	if !retry {
		if err := failMedia(ctx, tx, job.Type, job.MediaID, code, message, now); err != nil {
			return false, err
		}
	}
	return retry, tx.Commit()
}

// Recover 恢复进程异常退出遗留的全部运行中处理任务。
func (r *ProcessingRepository) Recover(ctx context.Context, now time.Time) error {
	return r.reclaimRunning(ctx, now, 0)
}

// ReclaimExpired 仅回收锁持有时间超过 lockTimeout 的运行中任务。
func (r *ProcessingRepository) ReclaimExpired(ctx context.Context, now time.Time, lockTimeout time.Duration) error {
	if lockTimeout <= 0 {
		return nil
	}
	return r.reclaimRunning(ctx, now, lockTimeout)
}

func (r *ProcessingRepository) reclaimRunning(ctx context.Context, now time.Time, lockTimeout time.Duration) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	expiredBefore := int64(0)
	if lockTimeout > 0 {
		expiredBefore = now.Add(-lockTimeout).UnixMilli()
	}
	_, err = tx.ExecContext(ctx, `UPDATE jobs SET status = 'pending', available_at_ms = ?, locked_at_ms = NULL,
        locked_by = NULL, updated_at_ms = ? WHERE job_type IN ('probe_media', 'generate_thumbnail', 'generate_card_thumbnail')
        AND status = 'running' AND attempt_count < max_attempts
        AND (? = 0 OR locked_at_ms IS NULL OR locked_at_ms <= ?)`,
		now.UnixMilli(), now.UnixMilli(), expiredBefore, expiredBefore)
	if err != nil {
		return fmt.Errorf("恢复媒体处理任务: %w", err)
	}
	rows, err := tx.QueryContext(ctx, `SELECT job_type, entity_id, COALESCE(error_code, 'PROCESSING_INTERRUPTED'),
        COALESCE(error_message, '媒体处理重试已耗尽') FROM jobs
        WHERE job_type IN ('probe_media', 'generate_thumbnail', 'generate_card_thumbnail') AND status = 'running' AND attempt_count >= max_attempts
        AND (? = 0 OR locked_at_ms IS NULL OR locked_at_ms <= ?)`, expiredBefore, expiredBefore)
	if err != nil {
		return err
	}
	type exhausted struct {
		// kind 是已耗尽任务的类型。
		kind string
		// mediaID 是任务关联的媒体标识。
		mediaID string
		// code 是任务失败错误码。
		code string
		// message 是任务失败信息。
		message string
	}
	var items []exhausted
	for rows.Next() {
		var item exhausted
		if err := rows.Scan(&item.kind, &item.mediaID, &item.code, &item.message); err != nil {
			rows.Close()
			return err
		}
		items = append(items, item)
	}
	if err := rows.Close(); err != nil {
		return err
	}
	for _, item := range items {
		if err := failMedia(ctx, tx, item.kind, item.mediaID, item.code, item.message, now); err != nil {
			return err
		}
	}
	_, err = tx.ExecContext(ctx, `UPDATE jobs SET status = 'failed', finished_at_ms = ?, locked_at_ms = NULL,
        locked_by = NULL, error_code = COALESCE(error_code, 'PROCESSING_INTERRUPTED'),
        error_message = COALESCE(error_message, '媒体处理重试已耗尽'), updated_at_ms = ?
        WHERE job_type IN ('probe_media', 'generate_thumbnail', 'generate_card_thumbnail') AND status = 'running' AND attempt_count >= max_attempts
        AND (? = 0 OR locked_at_ms IS NULL OR locked_at_ms <= ?)`,
		now.UnixMilli(), now.UnixMilli(), expiredBefore, expiredBefore)
	if err != nil {
		return err
	}
	return tx.Commit()
}

// ListOrphans 返回有效来源中缺少对应活跃任务的处理中媒体。
func (r *ProcessingRepository) ListOrphans(ctx context.Context, jobType string, limit int) ([]domain.MediaInput, error) {
	statuses := "'discovered','probing'"
	if jobType == domain.JobTypeThumbnail {
		statuses = "'thumbnailing'"
	} else if jobType == domain.JobTypeCardThumbnail {
		statuses = "'ready'"
	} else if jobType != domain.JobTypeProbe {
		return nil, nil
	}
	query := `SELECT mi.id, mi.source_id, s.root_path, mi.relative_path, mi.media_type, mi.file_size, mi.file_modified_at_ms,
		COALESCE(mi.duration_ms, 0)
        FROM media_items mi JOIN sources s ON s.id = mi.source_id
        WHERE mi.status IN (` + statuses + `) AND s.deleted_at_ms IS NULL AND s.enabled = 1
		AND (? <> 'generate_card_thumbnail' OR (EXISTS (SELECT 1 FROM media_assets d WHERE d.media_id=mi.id AND d.asset_type='thumbnail' AND d.variant='default' AND d.status='ready')
		AND NOT EXISTS (SELECT 1 FROM media_assets c WHERE c.media_id=mi.id AND c.asset_type='thumbnail' AND c.variant='card')))
        AND NOT EXISTS (SELECT 1 FROM jobs j WHERE j.job_type = ? AND j.entity_id = mi.id
        AND j.status IN ('pending', 'running')) ORDER BY mi.discovered_at_ms, mi.id LIMIT ?`
	rows, err := r.db.QueryContext(ctx, query, jobType, jobType, limit)
	if err != nil {
		return nil, fmt.Errorf("查询遗留媒体处理任务: %w", err)
	}
	defer rows.Close()
	var media []domain.MediaInput
	for rows.Next() {
		var item domain.MediaInput
		if err := rows.Scan(&item.ID, &item.SourceID, &item.RootPath, &item.RelativePath,
			&item.MediaType, &item.FileSize, &item.ModifiedAtMS, &item.DurationMS); err != nil {
			return nil, err
		}
		media = append(media, item)
	}
	return media, rows.Err()
}

func failMedia(ctx context.Context, tx *sql.Tx, jobType, mediaID, code, message string, now time.Time) error {
	if jobType == domain.JobTypeCardThumbnail {
		_, err := tx.ExecContext(ctx, `UPDATE media_assets SET status='failed', error_message=?, updated_at_ms=?
			WHERE media_id=? AND asset_type='thumbnail' AND variant='card'`, nullableText(message), now.UnixMilli(), mediaID)
		return err
	}
	_, err := tx.ExecContext(ctx, `UPDATE media_items SET status = 'failed', error_code = ?, error_message = ?,
        updated_at_ms = ? WHERE id = ? AND status <> 'missing'`, nullableText(code), nullableText(message), now.UnixMilli(), mediaID)
	if err == nil && jobType == domain.JobTypeThumbnail {
		_, err = tx.ExecContext(ctx, `UPDATE media_assets SET status = 'failed', error_message = ?, updated_at_ms = ?
            WHERE media_id = ? AND asset_type = 'thumbnail' AND variant = 'default'`, nullableText(message), now.UnixMilli(), mediaID)
	}
	return err
}
