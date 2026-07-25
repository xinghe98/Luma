// 扫描资料汇总将扫描关联的作品状态转换为 API 可直接展示的两阶段进度。
package sqlite

import (
	"context"
	"fmt"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// attachMetadataSummary 汇总本次扫描创建的资料运行；同步尚未创建运行时保持 waiting。
func (r *ScanRepository) attachMetadataSummary(ctx context.Context, job *domain.ScanJob) error {
	summary := &job.Metadata
	var exists int
	err := r.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM catalog_scrape_runs WHERE scan_job_id=?`, job.ID).Scan(&exists)
	if err != nil {
		return fmt.Errorf("读取扫描资料运行: %w", err)
	}
	if exists == 0 {
		summary.Status = "waiting"
		return nil
	}
	err = r.db.QueryRowContext(ctx, `SELECT COUNT(*),
		COALESCE(SUM(c.metadata_status='pending'),0),COALESCE(SUM(c.metadata_status='refreshing'),0),
		COALESCE(SUM(c.metadata_status='ready'),0),COALESCE(SUM(c.metadata_status='needs_review'),0),
		COALESCE(SUM(c.metadata_status='failed'),0)
		FROM catalog_scrape_run_items i JOIN catalog_items c ON c.id=i.catalog_item_id
		WHERE i.scan_job_id=?`, job.ID).Scan(&summary.Total, &summary.Pending, &summary.Refreshing,
		&summary.Ready, &summary.Unmatched, &summary.Failed)
	if err != nil {
		return fmt.Errorf("汇总扫描资料状态: %w", err)
	}
	if summary.Pending+summary.Refreshing > 0 {
		summary.Status = "running"
	} else if summary.Failed > 0 {
		summary.Status = "completed_with_errors"
	} else {
		summary.Status = "completed"
	}
	return nil
}
