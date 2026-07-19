package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// CreateJob 在同一事务内创建通用任务和扫描进度记录。
func (r *ScanRepository) CreateJob(ctx context.Context, job domain.ScanJob) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	nowMS := job.CreatedAt.UnixMilli()
	_, err = tx.ExecContext(ctx, `INSERT INTO jobs(
        id, job_type, entity_id, status, max_attempts, available_at_ms, created_at_ms, updated_at_ms
    ) VALUES (?, 'scan_source', ?, 'pending', 1, ?, ?, ?)`, job.ID, job.SourceID, nowMS, nowMS, nowMS)
	if err != nil {
		if isUniqueConstraint(err) {
			return domain.ErrScanAlreadyRunning
		}
		return fmt.Errorf("创建通用扫描任务: %w", err)
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO scan_jobs(
        id, source_id, status, phase, created_at_ms, updated_at_ms
    ) VALUES (?, ?, 'pending', 'queued', ?, ?)`, job.ID, job.SourceID, nowMS, nowMS)
	if err != nil {
		return fmt.Errorf("创建扫描任务: %w", err)
	}
	return tx.Commit()
}

// GetJob 根据任务标识读取扫描任务。
func (r *ScanRepository) GetJob(ctx context.Context, id string) (domain.ScanJob, error) {
	job, err := scanJob(r.db.QueryRowContext(ctx, scanJobSelect+` WHERE sj.id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.ScanJob{}, domain.ErrScanNotFound
	}
	if err == nil {
		err = r.attachProcessingSummary(ctx, &job)
	}
	return job, err
}

// LatestJob 返回指定媒体源或全局最近创建的扫描任务。
func (r *ScanRepository) LatestJob(ctx context.Context, sourceID string) (domain.ScanJob, error) {
	query := scanJobSelect
	args := []any{}
	if sourceID != "" {
		query += ` WHERE sj.source_id = ?`
		args = append(args, sourceID)
	}
	query += ` ORDER BY sj.created_at_ms DESC, sj.id DESC LIMIT 1`
	job, err := scanJob(r.db.QueryRowContext(ctx, query, args...))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.ScanJob{}, domain.ErrScanNotFound
	}
	if err == nil {
		err = r.attachProcessingSummary(ctx, &job)
	}
	return job, err
}

// ClaimNextJob 原子领取最早可运行的扫描任务。
func (r *ScanRepository) ClaimNextJob(ctx context.Context, workerID string, now time.Time) (domain.ScanJob, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.ScanJob{}, err
	}
	defer tx.Rollback()
	var id string
	err = tx.QueryRowContext(ctx, `SELECT id FROM jobs
        WHERE job_type = 'scan_source' AND status = 'pending' AND available_at_ms <= ?
        ORDER BY created_at_ms, id LIMIT 1`, now.UnixMilli()).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.ScanJob{}, domain.ErrNoPendingScan
	}
	if err != nil {
		return domain.ScanJob{}, fmt.Errorf("查询待执行扫描任务: %w", err)
	}
	result, err := tx.ExecContext(ctx, `UPDATE jobs SET status = 'running', attempt_count = attempt_count + 1,
        locked_at_ms = ?, locked_by = ?, updated_at_ms = ? WHERE id = ? AND status = 'pending'`,
		now.UnixMilli(), workerID, now.UnixMilli(), id)
	if err != nil {
		return domain.ScanJob{}, fmt.Errorf("领取扫描任务: %w", err)
	}
	if err := requireAffected(result, domain.ErrNoPendingScan); err != nil {
		return domain.ScanJob{}, err
	}
	_, err = tx.ExecContext(ctx, `UPDATE scan_jobs SET status = 'running', phase = 'walking',
        started_at_ms = ?, updated_at_ms = ? WHERE id = ?`, now.UnixMilli(), now.UnixMilli(), id)
	if err != nil {
		return domain.ScanJob{}, fmt.Errorf("更新扫描任务运行状态: %w", err)
	}
	job, err := scanJob(tx.QueryRowContext(ctx, scanJobSelect+` WHERE sj.id = ?`, id))
	if err != nil {
		return domain.ScanJob{}, err
	}
	if err := tx.Commit(); err != nil {
		return domain.ScanJob{}, err
	}
	return job, nil
}

// AddProgress 原子累加扫描统计数据。
func (r *ScanRepository) AddProgress(ctx context.Context, id string, discovered, processed, failed int64, now time.Time) error {
	result, err := r.db.ExecContext(ctx, `UPDATE scan_jobs SET
        discovered_count = discovered_count + ?, processed_count = processed_count + ?,
        failed_count = failed_count + ?, updated_at_ms = ? WHERE id = ? AND status = 'running'`,
		discovered, processed, failed, now.UnixMilli(), id)
	if err != nil {
		return err
	}
	return requireAffected(result, domain.ErrScanNotFound)
}

// MarkFileFailed 记录单文件失败，并保留同路径已有索引的 last_seen，避免成功收尾时误标 missing。
func (r *ScanRepository) MarkFileFailed(ctx context.Context, jobID, sourceID string, file domain.DiscoveredFile, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	nowMS := now.UnixMilli()
	result, err := tx.ExecContext(ctx, `UPDATE scan_jobs SET
        discovered_count = discovered_count + 1, failed_count = failed_count + 1, updated_at_ms = ?
        WHERE id = ? AND status = 'running'`, nowMS, jobID)
	if err != nil {
		return err
	}
	if err := requireAffected(result, domain.ErrScanNotFound); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE media_items SET last_seen_scan_id = ?, updated_at_ms = ?
        WHERE source_id = ? AND relative_path = ?`, jobID, nowMS, sourceID, file.RelativePath)
	if err != nil {
		return fmt.Errorf("保留失败文件索引水位: %w", err)
	}
	return tx.Commit()
}

// HasActiveJob 判断指定媒体源是否仍有 pending/running 扫描任务。
func (r *ScanRepository) HasActiveJob(ctx context.Context, sourceID string) (bool, error) {
	var count int
	err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM jobs
        WHERE job_type = 'scan_source' AND entity_id = ? AND status IN ('pending', 'running')`, sourceID).Scan(&count)
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

// CompleteJob 在一个事务中提交 missing、任务完成和媒体源扫描水位。
func (r *ScanRepository) CompleteJob(ctx context.Context, jobID, sourceID string, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	result, err := tx.ExecContext(ctx, `UPDATE scan_jobs SET status = 'completed', phase = 'completed',
        finished_at_ms = ?, updated_at_ms = ? WHERE id = ? AND source_id = ? AND status = 'running'`,
		now.UnixMilli(), now.UnixMilli(), jobID, sourceID)
	if err != nil {
		return err
	}
	if err := requireAffected(result, domain.ErrScanNotFound); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE media_items SET status = 'missing', missing_at_ms = ?, updated_at_ms = ?
        WHERE source_id = ? AND COALESCE(last_seen_scan_id, '') <> ? AND status <> 'missing'`,
		now.UnixMilli(), now.UnixMilli(), sourceID, jobID)
	if err != nil {
		return fmt.Errorf("提交 missing 标记: %w", err)
	}
	_, err = tx.ExecContext(ctx, `UPDATE jobs SET status = 'completed', finished_at_ms = ?,
        locked_at_ms = NULL, locked_by = NULL, updated_at_ms = ? WHERE id = ? AND status = 'running'`,
		now.UnixMilli(), now.UnixMilli(), jobID)
	if err != nil {
		return err
	}
	sourceStatus := domain.SourceStatusOnline
	var failedCount int64
	if err := tx.QueryRowContext(ctx, `SELECT failed_count FROM scan_jobs WHERE id = ?`, jobID).Scan(&failedCount); err != nil {
		return err
	}
	if failedCount > 0 {
		sourceStatus = domain.SourceStatusDegraded
	}
	_, err = tx.ExecContext(ctx, `UPDATE sources SET last_scan_id = ?, last_seen_at_ms = ?,
        status = ?, updated_at_ms = ? WHERE id = ?`, jobID, now.UnixMilli(), sourceStatus, now.UnixMilli(), sourceID)
	if err != nil {
		return err
	}
	return tx.Commit()
}

// FinishJobWithoutCommit 结束异常任务，且不会修改任何媒体 missing 状态。
func (r *ScanRepository) FinishJobWithoutCommit(
	ctx context.Context,
	jobID string,
	status string,
	errorCode string,
	errorMessage string,
	now time.Time,
) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	jobStatus := mapJobStatus(status)
	result, err := tx.ExecContext(ctx, `UPDATE scan_jobs SET status = ?, phase = 'finished', finished_at_ms = ?,
        error_code = ?, error_message = ?, updated_at_ms = ? WHERE id = ? AND status IN ('pending', 'running')`,
		status, now.UnixMilli(), nullableText(errorCode), nullableText(errorMessage), now.UnixMilli(), jobID)
	if err != nil {
		return err
	}
	if err := requireAffected(result, domain.ErrScanNotFound); err != nil {
		return err
	}
	result, err = tx.ExecContext(ctx, `UPDATE jobs SET status = ?, finished_at_ms = ?, error_code = ?, error_message = ?,
        locked_at_ms = NULL, locked_by = NULL, updated_at_ms = ? WHERE id = ? AND status IN ('pending', 'running')`,
		jobStatus, now.UnixMilli(), nullableText(errorCode), nullableText(errorMessage), now.UnixMilli(), jobID)
	if err != nil {
		return err
	}
	if err := requireAffected(result, domain.ErrScanNotFound); err != nil {
		return err
	}
	return tx.Commit()
}

// InterruptRunningJobs 将异常退出遗留的运行中扫描标记为 interrupted。
func (r *ScanRepository) InterruptRunningJobs(ctx context.Context, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `UPDATE scan_jobs SET status = 'interrupted', phase = 'finished',
        finished_at_ms = ?, error_code = 'SCAN_INTERRUPTED', error_message = '服务退出导致扫描中断', updated_at_ms = ?
        WHERE status = 'running'`, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE jobs SET status = 'interrupted', finished_at_ms = ?,
        error_code = 'SCAN_INTERRUPTED', error_message = '服务退出导致扫描中断',
        locked_at_ms = NULL, locked_by = NULL, updated_at_ms = ?
        WHERE job_type = 'scan_source' AND status = 'running'`, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return err
	}
	return tx.Commit()
}

// scanJobSelect 是扫描任务领域模型使用的统一查询字段。
const scanJobSelect = `SELECT sj.id, sj.source_id, sj.status, COALESCE(sj.phase, ''),
    sj.discovered_count, sj.processed_count, sj.failed_count, sj.started_at_ms, sj.finished_at_ms,
    COALESCE(sj.error_code, ''), COALESCE(sj.error_message, ''), sj.created_at_ms, sj.updated_at_ms
    FROM scan_jobs sj`

// mapJobStatus 将 scan_jobs 状态映射到 jobs 表允许的状态值。
func mapJobStatus(status string) string {
	switch status {
	case domain.ScanStatusCancelled:
		return domain.ScanStatusCancelled
	case domain.ScanStatusInterrupted:
		return domain.ScanStatusInterrupted
	case domain.ScanStatusCompleted:
		return domain.ScanStatusCompleted
	default:
		return domain.ScanStatusFailed
	}
}

// scanJob 将数据库行转换为扫描任务领域模型。
func scanJob(row rowScanner) (domain.ScanJob, error) {
	var job domain.ScanJob
	var started, finished sql.NullInt64
	var createdMS, updatedMS int64
	err := row.Scan(&job.ID, &job.SourceID, &job.Status, &job.Phase,
		&job.DiscoveredCount, &job.ProcessedCount, &job.FailedCount,
		&started, &finished, &job.ErrorCode, &job.ErrorMessage, &createdMS, &updatedMS)
	if err != nil {
		return domain.ScanJob{}, err
	}
	job.CreatedAt = time.UnixMilli(createdMS).UTC()
	job.UpdatedAt = time.UnixMilli(updatedMS).UTC()
	if started.Valid {
		value := time.UnixMilli(started.Int64).UTC()
		job.StartedAt = &value
	}
	if finished.Valid {
		value := time.UnixMilli(finished.Int64).UTC()
		job.FinishedAt = &value
	}
	return job, nil
}
