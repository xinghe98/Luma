// 扫描资料运行持久化一次扫描关联的作品，并将其安全地交给既有刮削队列。
package sqlite

import (
	"context"
	"fmt"
	"time"
)

// QueueMetadataForScan 在作品库同步完成后创建本次扫描的资料运行。
// 已有同一扫描的运行不会覆盖正在执行的任务，确保重复信号幂等。
func (r *CatalogRepository) QueueMetadataForScan(ctx context.Context, scanID, sourceID string, now time.Time) (int, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	result, err := tx.ExecContext(ctx, `INSERT INTO catalog_scrape_runs(scan_job_id,source_id,created_at_ms)
		VALUES(?,?,?) ON CONFLICT(scan_job_id) DO NOTHING`, scanID, sourceID, now.UnixMilli())
	if err != nil {
		return 0, fmt.Errorf("创建扫描资料运行: %w", err)
	}
	if count, _ := result.RowsAffected(); count == 0 {
		return 0, tx.Commit()
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO catalog_scrape_run_items(scan_job_id,catalog_item_id)
		SELECT ?, c.id FROM catalog_items c
		WHERE c.source_id=? AND c.metadata_status IN ('pending','refreshing','failed','needs_review')
		AND EXISTS (
			SELECT 1 FROM catalog_media_links l JOIN media_items m ON m.id=l.media_id
			WHERE l.catalog_item_id=c.id AND l.match_status='matched'
			AND m.source_id=? AND m.last_seen_scan_id=? AND m.status<>'missing'
		)`, scanID, sourceID, sourceID, scanID)
	if err != nil {
		return 0, fmt.Errorf("关联扫描资料作品: %w", err)
	}
	var count int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM catalog_scrape_run_items WHERE scan_job_id=?`, scanID).Scan(&count); err != nil {
		return 0, err
	}
	if count > 0 {
		_, err = tx.ExecContext(ctx, `UPDATE catalog_items SET metadata_status='pending',metadata_error_code=NULL,
			metadata_error_message=NULL,updated_at_ms=?
			WHERE id IN (SELECT catalog_item_id FROM catalog_scrape_run_items WHERE scan_job_id=?)
			AND metadata_status <> 'refreshing'`, now.UnixMilli(), scanID)
		if err != nil {
			return 0, err
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO catalog_scrape_jobs(
			catalog_item_id,status,attempt_count,available_at_ms,created_at_ms,updated_at_ms
		) SELECT catalog_item_id,'pending',0,?,?,? FROM catalog_scrape_run_items WHERE scan_job_id=?
		ON CONFLICT(catalog_item_id) DO UPDATE SET
			status=CASE WHEN catalog_scrape_jobs.status='running' THEN 'running' ELSE 'pending' END,
			attempt_count=CASE WHEN catalog_scrape_jobs.status='running' THEN catalog_scrape_jobs.attempt_count ELSE 0 END,
			available_at_ms=CASE WHEN catalog_scrape_jobs.status='running' THEN catalog_scrape_jobs.available_at_ms ELSE excluded.available_at_ms END,
			locked_at_ms=CASE WHEN catalog_scrape_jobs.status='running' THEN catalog_scrape_jobs.locked_at_ms ELSE NULL END,
			locked_by=CASE WHEN catalog_scrape_jobs.status='running' THEN catalog_scrape_jobs.locked_by ELSE NULL END,
			error_code=CASE WHEN catalog_scrape_jobs.status='running' THEN catalog_scrape_jobs.error_code ELSE NULL END,
			error_message=CASE WHEN catalog_scrape_jobs.status='running' THEN catalog_scrape_jobs.error_message ELSE NULL END,
			finished_at_ms=CASE WHEN catalog_scrape_jobs.status='running' THEN catalog_scrape_jobs.finished_at_ms ELSE NULL END,
			updated_at_ms=excluded.updated_at_ms`, now.UnixMilli(), now.UnixMilli(), now.UnixMilli(), scanID)
		if err != nil {
			return 0, fmt.Errorf("入队扫描资料任务: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return count, nil
}
