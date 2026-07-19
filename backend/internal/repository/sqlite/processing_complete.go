package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// CompleteProbe 仅在文件版本未变化时提交元数据、缩略图资产和后续任务。
func (r *ProcessingRepository) CompleteProbe(ctx context.Context, job domain.ProcessingJob, media domain.MediaInput,
	probe domain.ProbeResult, assetID, thumbnailJobID, storageKey string, now time.Time) (bool, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	matched, err := mediaVersionMatches(ctx, tx, job, media)
	if err != nil {
		return false, err
	}
	if !matched {
		if err := cancelStaleJob(ctx, tx, job, now); err != nil {
			return false, err
		}
		return false, tx.Commit()
	}
	var captured any
	if probe.CapturedAt != nil {
		captured = probe.CapturedAt.UnixMilli()
	}
	result, err := tx.ExecContext(ctx, `UPDATE media_items SET detected_title = ?, mime_type = ?, duration_ms = ?,
        width = ?, height = ?, video_codec = ?, audio_codec = ?, container = ?, bitrate = ?,
        frame_rate_num = ?, frame_rate_den = ?, audio_track_count = ?, orientation = ?, captured_at_ms = ?,
        probe_data = ?, probe_version = ?, status = 'thumbnailing', error_code = NULL, error_message = NULL,
        updated_at_ms = ? WHERE id = ? AND file_size = ? AND file_modified_at_ms = ?`,
		nullableText(probe.Title), nullableText(probe.MIMEType), probe.DurationMS, probe.Width, probe.Height,
		nullableText(probe.VideoCodec), nullableText(probe.AudioCodec), nullableText(probe.Container), probe.Bitrate,
		probe.FrameRateNum, probe.FrameRateDen, probe.AudioTrackCount, probe.Orientation, captured,
		string(probe.RawJSON), probe.Version, now.UnixMilli(), media.ID, media.FileSize, media.ModifiedAtMS)
	if err != nil {
		return false, fmt.Errorf("提交媒体探测元数据: %w", err)
	}
	if err := requireAffected(result, domain.ErrMediaNotFound); err != nil {
		return false, err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO media_assets(
        id, media_id, asset_type, variant, storage_key, status, generator_version, created_at_ms, updated_at_ms
    ) VALUES (?, ?, 'thumbnail', 'default', ?, 'pending', 1, ?, ?)
    ON CONFLICT(media_id, asset_type, variant, generator_version) DO UPDATE SET
        storage_key = excluded.storage_key,
        status = CASE WHEN media_assets.status = 'ready' THEN 'ready' ELSE 'pending' END,
        error_message = NULL, updated_at_ms = excluded.updated_at_ms`,
		assetID, media.ID, storageKey, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return false, fmt.Errorf("准备缩略图资产: %w", err)
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO jobs(
        id, job_type, entity_id, status, max_attempts, available_at_ms, created_at_ms, updated_at_ms
    ) VALUES (?, 'generate_thumbnail', ?, 'pending', 2, ?, ?, ?)
    ON CONFLICT DO NOTHING`, thumbnailJobID, media.ID, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return false, fmt.Errorf("创建缩略图任务: %w", err)
	}
	if err := completeJob(ctx, tx, job, now); err != nil {
		return false, err
	}
	return true, tx.Commit()
}

// CompleteThumbnail 仅在文件版本未变化时将默认资产和媒体标记为 ready。
func (r *ProcessingRepository) CompleteThumbnail(ctx context.Context, job domain.ProcessingJob, media domain.MediaInput,
	thumbnail domain.ThumbnailResult, now time.Time) (bool, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return false, err
	}
	defer tx.Rollback()
	matched, err := mediaVersionMatches(ctx, tx, job, media)
	if err != nil {
		return false, err
	}
	if !matched {
		if err := cancelStaleJob(ctx, tx, job, now); err != nil {
			return false, err
		}
		return false, tx.Commit()
	}
	result, err := tx.ExecContext(ctx, `UPDATE media_assets SET storage_key = ?, mime_type = ?, width = ?, height = ?,
        content_sha256 = ?, status = 'ready', error_message = NULL, updated_at_ms = ?
        WHERE media_id = ? AND asset_type = 'thumbnail' AND variant = 'default' AND generator_version = 1`,
		thumbnail.StorageKey, nullableText(thumbnail.MIMEType), thumbnail.Width, thumbnail.Height,
		nullableText(thumbnail.ContentSHA256), now.UnixMilli(), media.ID)
	if err != nil {
		return false, fmt.Errorf("完成缩略图资产: %w", err)
	}
	if err := requireAffected(result, domain.ErrMediaNotFound); err != nil {
		return false, err
	}
	result, err = tx.ExecContext(ctx, `UPDATE media_items SET status = 'ready', indexed_at_ms = ?,
        error_code = NULL, error_message = NULL, updated_at_ms = ?
        WHERE id = ? AND file_size = ? AND file_modified_at_ms = ?`,
		now.UnixMilli(), now.UnixMilli(), media.ID, media.FileSize, media.ModifiedAtMS)
	if err != nil {
		return false, fmt.Errorf("完成媒体处理: %w", err)
	}
	if err := requireAffected(result, domain.ErrMediaNotFound); err != nil {
		return false, err
	}
	if err := completeJob(ctx, tx, job, now); err != nil {
		return false, err
	}
	return true, tx.Commit()
}

func mediaVersionMatches(ctx context.Context, tx *sql.Tx, job domain.ProcessingJob, media domain.MediaInput) (bool, error) {
	var count int
	err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM jobs j JOIN media_items mi ON mi.id = j.entity_id
        WHERE j.id = ? AND j.job_type = ? AND j.entity_id = ? AND j.status = 'running'
        AND mi.id = ? AND mi.file_size = ? AND mi.file_modified_at_ms = ? AND mi.status <> 'missing'`,
		job.ID, job.Type, job.MediaID, media.ID, media.FileSize, media.ModifiedAtMS).Scan(&count)
	return count == 1, err
}
