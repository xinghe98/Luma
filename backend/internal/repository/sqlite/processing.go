package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// ProcessingRepository 持久化媒体探测与缩略图任务。
type ProcessingRepository struct {
	// db 是媒体处理任务使用的数据库连接。
	db *sql.DB
}

// NewProcessingRepository 创建 SQLite 媒体处理 Repository。
func NewProcessingRepository(db *sql.DB) (*ProcessingRepository, error) {
	if db == nil {
		return nil, fmt.Errorf("数据库不能为空")
	}
	return &ProcessingRepository{db: db}, nil
}

// EnqueueProbe 创建最多执行两次的探测任务。
func (r *ProcessingRepository) EnqueueProbe(ctx context.Context, jobID, mediaID string, now time.Time) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO jobs(
        id, job_type, entity_id, status, max_attempts, available_at_ms, created_at_ms, updated_at_ms
    ) VALUES (?, 'probe_media', ?, 'pending', 2, ?, ?, ?)
    ON CONFLICT DO NOTHING`, jobID, mediaID, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return fmt.Errorf("创建媒体探测任务: %w", err)
	}
	return nil
}

// EnqueueThumbnail 确保默认缩略图资产存在并创建最多执行两次的缩略图任务。
func (r *ProcessingRepository) EnqueueThumbnail(ctx context.Context, jobID, mediaID, assetID, storageKey string, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `INSERT INTO media_assets(
        id, media_id, asset_type, variant, storage_key, status, generator_version, created_at_ms, updated_at_ms
    ) VALUES (?, ?, 'thumbnail', 'default', ?, 'pending', 1, ?, ?)
    ON CONFLICT(media_id, asset_type, variant, generator_version) DO UPDATE SET
        storage_key = excluded.storage_key, status = 'pending', error_message = NULL, updated_at_ms = excluded.updated_at_ms
        WHERE media_assets.status <> 'ready'`,
		assetID, mediaID, storageKey, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return fmt.Errorf("准备缩略图资产: %w", err)
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO jobs(
        id, job_type, entity_id, status, max_attempts, available_at_ms, created_at_ms, updated_at_ms
    ) VALUES (?, 'generate_thumbnail', ?, 'pending', 2, ?, ?, ?)
    ON CONFLICT DO NOTHING`, jobID, mediaID, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return fmt.Errorf("创建缩略图任务: %w", err)
	}
	return tx.Commit()
}

// EnqueueCardThumbnail 创建独立的卡片缩略图补齐资产与任务。
func (r *ProcessingRepository) EnqueueCardThumbnail(ctx context.Context, jobID, mediaID, assetID, storageKey string, now time.Time) error {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `INSERT INTO media_assets(
        id, media_id, asset_type, variant, storage_key, status, generator_version, created_at_ms, updated_at_ms
    ) VALUES (?, ?, 'thumbnail', 'card', ?, 'pending', 1, ?, ?)
    ON CONFLICT(media_id, asset_type, variant, generator_version) DO UPDATE SET
        storage_key=excluded.storage_key, status='pending', error_message=NULL, updated_at_ms=excluded.updated_at_ms
        WHERE media_assets.status <> 'ready'`, assetID, mediaID, storageKey, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return fmt.Errorf("准备卡片缩略图资产: %w", err)
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO jobs(
        id, job_type, entity_id, status, max_attempts, available_at_ms, created_at_ms, updated_at_ms
    ) VALUES (?, 'generate_card_thumbnail', ?, 'pending', 2, ?, ?, ?) ON CONFLICT DO NOTHING`,
		jobID, mediaID, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return fmt.Errorf("创建卡片缩略图任务: %w", err)
	}
	return tx.Commit()
}

// Claim 原子领取指定类型的最早可运行任务，并同步媒体处理状态。
func (r *ProcessingRepository) Claim(ctx context.Context, jobType, workerID string, now time.Time) (domain.ProcessingJob, error) {
	if jobType != domain.JobTypeProbe && jobType != domain.JobTypeThumbnail && jobType != domain.JobTypeCardThumbnail {
		return domain.ProcessingJob{}, domain.ErrNoPendingJob
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.ProcessingJob{}, err
	}
	defer tx.Rollback()
	var job domain.ProcessingJob
	err = tx.QueryRowContext(ctx, `SELECT id, job_type, entity_id, attempt_count + 1, max_attempts
        FROM jobs WHERE job_type = ? AND status = 'pending' AND available_at_ms <= ?
        ORDER BY created_at_ms, id LIMIT 1`, jobType, now.UnixMilli()).Scan(
		&job.ID, &job.Type, &job.MediaID, &job.Attempt, &job.MaxAttempts)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.ProcessingJob{}, domain.ErrNoPendingJob
	}
	if err != nil {
		return domain.ProcessingJob{}, fmt.Errorf("查询待执行媒体任务: %w", err)
	}
	result, err := tx.ExecContext(ctx, `UPDATE jobs SET status = 'running', attempt_count = attempt_count + 1,
        locked_at_ms = ?, locked_by = ?, updated_at_ms = ? WHERE id = ? AND status = 'pending'`,
		now.UnixMilli(), workerID, now.UnixMilli(), job.ID)
	if err != nil {
		return domain.ProcessingJob{}, fmt.Errorf("领取媒体任务: %w", err)
	}
	if err := requireAffected(result, domain.ErrNoPendingJob); err != nil {
		return domain.ProcessingJob{}, err
	}
	status := domain.MediaStatusProbing
	if jobType == domain.JobTypeThumbnail {
		status = domain.MediaStatusThumbnailing
	}
	if jobType != domain.JobTypeCardThumbnail {
		_, err = tx.ExecContext(ctx, `UPDATE media_items SET status = ?, error_code = NULL,
        error_message = NULL, updated_at_ms = ? WHERE id = ? AND status <> 'missing'`,
			status, now.UnixMilli(), job.MediaID)
		if err != nil {
			return domain.ProcessingJob{}, fmt.Errorf("更新媒体处理状态: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return domain.ProcessingJob{}, err
	}
	// 后续完成或失败必须带回同一领取者，防止过期 worker 覆盖重新领取的任务。
	job.WorkerID = workerID
	return job, nil
}

// GetMedia 返回有效来源中的媒体文件定位和版本信息。
func (r *ProcessingRepository) GetMedia(ctx context.Context, id string) (domain.MediaInput, error) {
	var media domain.MediaInput
	err := r.db.QueryRowContext(ctx, `SELECT mi.id, mi.source_id, s.root_path, mi.relative_path,
		mi.media_type, mi.file_size, mi.file_modified_at_ms, COALESCE(mi.duration_ms, 0) FROM media_items mi
        JOIN sources s ON s.id = mi.source_id
        WHERE mi.id = ? AND mi.status <> 'missing' AND s.deleted_at_ms IS NULL AND s.enabled = 1`, id).Scan(
		&media.ID, &media.SourceID, &media.RootPath, &media.RelativePath, &media.MediaType,
		&media.FileSize, &media.ModifiedAtMS, &media.DurationMS)
	if errors.Is(err, sql.ErrNoRows) {
		return domain.MediaInput{}, domain.ErrMediaNotFound
	}
	if err != nil {
		return domain.MediaInput{}, fmt.Errorf("读取媒体处理输入: %w", err)
	}
	return media, nil
}

func completeJob(ctx context.Context, tx *sql.Tx, job domain.ProcessingJob, now time.Time) error {
	result, err := tx.ExecContext(ctx, `UPDATE jobs SET status = 'completed', finished_at_ms = ?,
        locked_at_ms = NULL, locked_by = NULL, error_code = NULL, error_message = NULL, updated_at_ms = ?
        WHERE id = ? AND job_type = ? AND entity_id = ? AND status = 'running'
        AND locked_by = ? AND attempt_count = ?`,
		now.UnixMilli(), now.UnixMilli(), job.ID, job.Type, job.MediaID, job.WorkerID, job.Attempt)
	if err != nil {
		return err
	}
	return requireAffected(result, domain.ErrNoPendingJob)
}

func cancelStaleJob(ctx context.Context, tx *sql.Tx, job domain.ProcessingJob, now time.Time) error {
	_, err := tx.ExecContext(ctx, `UPDATE jobs SET status = 'cancelled', finished_at_ms = ?,
		locked_at_ms = NULL, locked_by = NULL, error_code = 'MEDIA_CHANGED',
		error_message = '媒体文件已变化', updated_at_ms = ?
		WHERE id = ? AND job_type = ? AND entity_id = ? AND status = 'running'
		AND locked_by = ? AND attempt_count = ?`,
		now.UnixMilli(), now.UnixMilli(), job.ID, job.Type, job.MediaID, job.WorkerID, job.Attempt)
	return err
}
