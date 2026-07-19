package sqlite

import (
	"context"
	"fmt"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// attachProcessingSummary 汇总本次扫描最后确认存在的媒体处理状态。
func (r *ScanRepository) attachProcessingSummary(ctx context.Context, job *domain.ScanJob) error {
	summary := &job.Processing
	err := r.db.QueryRowContext(ctx, `SELECT COUNT(*),
		COALESCE(SUM(status = 'discovered'), 0), COALESCE(SUM(status = 'probing'), 0),
		COALESCE(SUM(status = 'thumbnailing'), 0), COALESCE(SUM(status = 'ready'), 0),
		COALESCE(SUM(status = 'failed'), 0)
		FROM media_items WHERE last_seen_scan_id = ? AND status <> 'missing'`, job.ID).Scan(
		&summary.Total, &summary.Discovered, &summary.Probing, &summary.Thumbnailing,
		&summary.Ready, &summary.Failed)
	if err != nil {
		return fmt.Errorf("汇总媒体处理状态: %w", err)
	}
	summary.Status = processingStatus(job.Status, *summary)
	return nil
}

func processingStatus(scanStatus string, summary domain.ProcessingSummary) string {
	active := summary.Discovered + summary.Probing + summary.Thumbnailing
	if active > 0 {
		return "running"
	}
	if scanStatus == domain.ScanStatusPending || scanStatus == domain.ScanStatusRunning {
		return "pending"
	}
	if summary.Failed > 0 {
		return "completed_with_errors"
	}
	return "completed"
}
