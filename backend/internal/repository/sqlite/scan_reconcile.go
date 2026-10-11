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

// IndexUpload 把上传已落盘的文件同步登记到 media_items，并在需要重新探测时入队 probe。
// 整个登记与入队在同一个事务内提交：任何一步失败都不会留下孤儿索引或缺失任务。
// last_seen_scan_id 取事务内查到的当前运行中扫描 ID；没有运行中扫描时为 NULL。
// 这样上传落在扫描进行中时不会被本轮 CompleteJob 误标 missing，而扫描结束后的
// 文件删除会由下一轮完整扫描按既有水位规则正常标记 missing。
func (r *ScanRepository) IndexUpload(
	ctx context.Context,
	sourceID string,
	newMediaID string,
	file domain.DiscoveredFile,
	now time.Time,
	probeJobID string,
) (domain.ReconcileResult, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return domain.ReconcileResult{}, err
	}
	defer tx.Rollback()
	// 在同一事务内读取该来源当前运行中的扫描任务；SQLite 串行化写事务，
	// 若 CompleteJob 已先提交则读不到 running，上传行走正常扫描水位。
	var scanID sql.NullString
	if err := tx.QueryRowContext(ctx, `SELECT id FROM jobs
		WHERE job_type = 'scan_source' AND entity_id = ? AND status = 'running' ORDER BY created_at_ms DESC LIMIT 1`,
		sourceID).Scan(&scanID); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return domain.ReconcileResult{}, err
	}
	result, err := reconcileFileTx(ctx, tx, scanID, sourceID, newMediaID, file, now, false)
	if err != nil {
		return domain.ReconcileResult{}, err
	}
	if result.NeedsProbe {
		if err := enqueueProbeTx(ctx, tx, probeJobID, result.MediaID, now); err != nil {
			return domain.ReconcileResult{}, err
		}
	}
	if err := tx.Commit(); err != nil {
		return domain.ReconcileResult{}, err
	}
	return result, nil
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
	result, err := reconcileFileTx(ctx, tx, sql.NullString{String: scanID, Valid: scanID != ""}, sourceID, newMediaID, file, now, true)
	if err != nil {
		return domain.ReconcileResult{}, err
	}
	if err := tx.Commit(); err != nil {
		return domain.ReconcileResult{}, err
	}
	return result, nil
}

// reconcileFileTx 在给定事务内执行媒体索引 reconcile；last_seen_scan_id 取入参，
// 为空时写入 NULL，表示尚无完整扫描见证该文件。
// forScan 为 true 时（扫描回调路径）先核对删除墓碑：删除发生前已启动的
// 扫描对同路径的过期快照一律拒绝，防止已删文件复活；上传索引入队传 false，
// 已发布的新文件不受旧扫描水位限制，也不清除墓碑。
func reconcileFileTx(
	ctx context.Context,
	tx *sql.Tx,
	scanID sql.NullString,
	sourceID string,
	newMediaID string,
	file domain.DiscoveredFile,
	now time.Time,
	forScan bool,
) (domain.ReconcileResult, error) {
	if forScan {
		stale, err := isStaleDeletedFile(ctx, tx, scanID, sourceID, file)
		if err != nil {
			return domain.ReconcileResult{}, err
		}
		if stale {
			// 过期快照：媒体已被用户删除，本次发现直接忽略，
			// 不创建索引行、不投递 probe，墓碑保留以防后续快照再次复活。
			return domain.ReconcileResult{Change: "unchanged"}, nil
		}
	}
	existing, found, ambiguous, err := findExistingMedia(ctx, tx, sourceID, file, now)
	if err != nil {
		return domain.ReconcileResult{}, err
	}
	if !found || ambiguous {
		if err := ensurePathAvailable(ctx, tx, sourceID, file.RelativePath, "", now); err != nil {
			return domain.ReconcileResult{}, err
		}
		_, err := tx.ExecContext(ctx, `INSERT INTO media_items(
            id, source_id, relative_path, filename, media_type, file_size, file_modified_at_ms, file_created_at_ms,
            file_id, quick_hash, status, last_seen_scan_id, discovered_at_ms, created_at_ms, updated_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'discovered', ?, ?, ?, ?)`,
			newMediaID, sourceID, file.RelativePath, file.Filename, file.MediaType, file.Size,
			file.ModifiedAt.UnixMilli(), nullableTimeMS(file.CreatedAt), nullableText(file.FileID), nullableText(file.QuickHash),
			scanID, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
		if err != nil {
			return domain.ReconcileResult{}, fmt.Errorf("创建媒体索引: %w", err)
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
        file_size = ?, file_modified_at_ms = ?, file_created_at_ms = COALESCE(?, file_created_at_ms),
        file_id = ?, quick_hash = ?, status = ?,
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
		file.ModifiedAt.UnixMilli(), nullableTimeMS(file.CreatedAt), nullableText(fileID), nullableText(quickHash), status,
		needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe,
		needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe, needsProbe,
		scanID, now.UnixMilli(), existing.ID)
	if err != nil {
		return domain.ReconcileResult{}, fmt.Errorf("更新媒体索引: %w", err)
	}
	return domain.ReconcileResult{MediaID: existing.ID, Change: change, NeedsProbe: needsProbe}, nil
}

// isStaleDeletedFile 判定当前扫描对同路径的发现是否属于已删文件的过期快照。
// 判定以删除时刻为水位：墓碑记录 deleted_at_ms，当前扫描任务的
// scan_jobs.created_at_ms 不晚于该时刻，说明扫描在删除前已启动，
// 其枚举快照不可信，拒绝复活；创建时间更晚的扫描是删除后新启动的，
// 即使发现 mtime/size 完全相同的文件也正常入库，并顺带清掉墓碑。
// 每源同一时刻只有一个活跃扫描，后启动的扫描执行时旧扫描必然已结束，
// 因此晚水位清理墓碑不会让旧扫描的迟到回包有机可乘。
func isStaleDeletedFile(ctx context.Context, tx *sql.Tx, scanID sql.NullString, sourceID string, file domain.DiscoveredFile) (bool, error) {
	if !scanID.Valid || scanID.String == "" {
		return false, nil
	}
	var deletedAtMS int64
	err := tx.QueryRowContext(ctx, `SELECT deleted_at_ms FROM media_delete_tombstones
        WHERE source_id = ? AND relative_path = ?`, sourceID, file.RelativePath).Scan(&deletedAtMS)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("查询删除墓碑: %w", err)
	}
	var scanCreatedMS int64
	err = tx.QueryRowContext(ctx, `SELECT created_at_ms FROM scan_jobs WHERE id = ?`, scanID.String).Scan(&scanCreatedMS)
	if errors.Is(err, sql.ErrNoRows) {
		// 找不到扫描记录时不按过期处理，交给既有 reconcile 语义收敛。
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("查询扫描任务创建时间: %w", err)
	}
	if scanCreatedMS <= deletedAtMS {
		// 扫描早于删除启动，枚举到的是已删文件的过期快照。
		return true, nil
	}
	// 删除后新启动的扫描：墓碑使命结束，顺手清理；
	// 每源串行扫描保证旧扫描不会再有迟到回包。
	if _, err := tx.ExecContext(ctx, `DELETE FROM media_delete_tombstones
        WHERE source_id = ? AND relative_path = ?`, sourceID, file.RelativePath); err != nil {
		return false, fmt.Errorf("清理删除墓碑: %w", err)
	}
	return false, nil
}

// enqueueProbeTx 在给定事务内创建最多执行两次的探测任务。
// 与 ProcessingRepository.EnqueueProbe 保持一致的 INSERT 语义；
// 独立成事务版本供上传索引与入队原子提交。
func enqueueProbeTx(ctx context.Context, tx *sql.Tx, jobID, mediaID string, now time.Time) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO jobs(
        id, job_type, entity_id, status, max_attempts, available_at_ms, created_at_ms, updated_at_ms
    ) VALUES (?, 'probe_media', ?, 'pending', 2, ?, ?, ?)
    ON CONFLICT DO NOTHING`, jobID, mediaID, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
	if err != nil {
		return fmt.Errorf("创建媒体探测任务: %w", err)
	}
	return nil
}
