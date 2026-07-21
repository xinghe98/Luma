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

// NeedsQuickHash 判断路径和文件 ID 无法直接识别文件时是否需要快速指纹。
func (r *ScanRepository) NeedsQuickHash(ctx context.Context, sourceID string, file domain.DiscoveredFile) (bool, error) {
	var count int
	item, err := queryOneMedia(ctx, r.db, `WHERE source_id = ? AND relative_path = ?`, sourceID, file.RelativePath)
	if err == nil {
		// 路径命中但身份冲突时，仍可能需要指纹去匹配“搬走”的旧文件。
		if !identityConflict(item, file) {
			return false, nil
		}
	} else if !errors.Is(err, sql.ErrNoRows) {
		return false, err
	}
	if file.FileID != "" {
		if err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM (
        SELECT id FROM media_items WHERE source_id = ? AND file_id = ? LIMIT 2
    )`, sourceID, file.FileID).Scan(&count); err != nil {
			return false, err
		}
		if count == 1 {
			return false, nil
		}
	}
	// 仅在存在同大小且已有指纹的候选时才计算，避免无意义 IO。
	if err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM media_items
        WHERE source_id = ? AND file_size = ? AND quick_hash IS NOT NULL`, sourceID, file.Size).Scan(&count); err != nil {
		return false, err
	}
	return count > 0, nil
}

// ReconcileFile 按文档规定的身份优先级新增或更新媒体索引。
func (r *ScanRepository) ReconcileFile(
	ctx context.Context,
	scanID string,
	sourceID string,
	newMediaID string,
	file domain.DiscoveredFile,
	now time.Time,
) (domain.ReconcileResult, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.ReconcileResult{}, err
	}
	defer tx.Rollback()
	existing, found, ambiguous, err := findExistingMedia(ctx, tx, sourceID, file, now)
	if err != nil {
		return domain.ReconcileResult{}, err
	}
	if !found || ambiguous {
		if err := ensurePathAvailable(ctx, tx, sourceID, file.RelativePath, "", now); err != nil {
			return domain.ReconcileResult{}, err
		}
		_, err := tx.ExecContext(ctx, `INSERT INTO media_items(
            id, source_id, relative_path, filename, media_type, file_size, file_modified_at_ms,
            file_id, quick_hash, status, last_seen_scan_id, discovered_at_ms, created_at_ms, updated_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'discovered', ?, ?, ?, ?)`,
			newMediaID, sourceID, file.RelativePath, file.Filename, file.MediaType, file.Size,
			file.ModifiedAt.UnixMilli(), nullableText(file.FileID), nullableText(file.QuickHash), scanID,
			now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
		if err != nil {
			return domain.ReconcileResult{}, fmt.Errorf("创建媒体索引: %w", err)
		}
		if err := tx.Commit(); err != nil {
			return domain.ReconcileResult{}, err
		}
		return domain.ReconcileResult{MediaID: newMediaID, Change: "created", NeedsProbe: true}, nil
	}

	if err := ensurePathAvailable(ctx, tx, sourceID, file.RelativePath, existing.ID, now); err != nil {
		return domain.ReconcileResult{}, err
	}
	contentChanged := existing.Size != file.Size || existing.ModifiedAtMS != file.ModifiedAt.UnixMilli() || existing.MediaType != file.MediaType
	moved := existing.RelativePath != file.RelativePath && !strings.HasPrefix(existing.RelativePath, displacedPathPrefix)
	// 若此前因冲突被挪到 displaced 路径，恢复到真实路径也视为 moved。
	if strings.HasPrefix(existing.RelativePath, displacedPathPrefix) {
		moved = true
	}
	change := "unchanged"
	if contentChanged {
		change = "updated"
	} else if moved {
		change = "moved"
	}
	fileID := file.FileID
	if fileID == "" && !contentChanged {
		fileID = existing.FileID
	}
	quickHash := file.QuickHash
	if quickHash == "" && !contentChanged {
		quickHash = existing.QuickHash
	}
	status := existing.Status
	needsProbe := contentChanged || status == domain.MediaStatusMissing || status == domain.MediaStatusFailed
	if needsProbe {
		status = domain.MediaStatusDiscovered
		_, err = tx.ExecContext(ctx, `UPDATE jobs SET status = 'cancelled', finished_at_ms = ?,
			locked_at_ms = NULL, locked_by = NULL, error_code = 'MEDIA_CHANGED',
			error_message = '媒体文件已变化', updated_at_ms = ?
			WHERE entity_id = ? AND job_type IN ('probe_media', 'generate_thumbnail', 'generate_card_thumbnail')
			AND status IN ('pending', 'running')`, now.UnixMilli(), now.UnixMilli(), existing.ID)
		if err != nil {
			return domain.ReconcileResult{}, fmt.Errorf("取消过期媒体任务: %w", err)
		}
	}
	_, err = tx.ExecContext(ctx, `UPDATE media_items SET relative_path = ?, filename = ?, media_type = ?,
        file_size = ?, file_modified_at_ms = ?, file_id = ?, quick_hash = ?, status = ?,
		detected_title = CASE WHEN ? THEN NULL ELSE detected_title END,
		mime_type = CASE WHEN ? THEN NULL ELSE mime_type END,
		duration_ms = CASE WHEN ? THEN NULL ELSE duration_ms END,
		width = CASE WHEN ? THEN NULL ELSE width END, height = CASE WHEN ? THEN NULL ELSE height END,
		video_codec = CASE WHEN ? THEN NULL ELSE video_codec END, audio_codec = CASE WHEN ? THEN NULL ELSE audio_codec END,
		container = CASE WHEN ? THEN NULL ELSE container END, bitrate = CASE WHEN ? THEN NULL ELSE bitrate END,
		frame_rate_num = CASE WHEN ? THEN NULL ELSE frame_rate_num END,
		frame_rate_den = CASE WHEN ? THEN NULL ELSE frame_rate_den END,
		audio_track_count = CASE WHEN ? THEN NULL ELSE audio_track_count END,
		orientation = CASE WHEN ? THEN NULL ELSE orientation END,
		captured_at_ms = CASE WHEN ? THEN NULL ELSE captured_at_ms END,
		probe_data = CASE WHEN ? THEN NULL ELSE probe_data END,
		indexed_at_ms = CASE WHEN ? THEN NULL ELSE indexed_at_ms END,
        error_code = NULL, error_message = NULL, last_seen_scan_id = ?, missing_at_ms = NULL, updated_at_ms = ?
        WHERE id = ?`, file.RelativePath, file.Filename, file.MediaType, file.Size,
		file.ModifiedAt.UnixMilli(), nullableText(fileID), nullableText(quickHash), status,
		needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe,
		needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe,
		scanID, now.UnixMilli(), existing.ID)
	if err != nil {
		return domain.ReconcileResult{}, fmt.Errorf("更新媒体索引: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return domain.ReconcileResult{}, err
	}
	return domain.ReconcileResult{MediaID: existing.ID, Change: change, NeedsProbe: needsProbe}, nil
}
