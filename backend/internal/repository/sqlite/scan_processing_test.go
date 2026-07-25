package sqlite

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestScanJobIncludesProcessingSummary(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(100, 0).UTC()
	source := createTestSource(t, sources, now)
	job := createAndClaimScan(t, scans, source.ID, "scan_processing", now)
	statuses := []string{
		domain.MediaStatusDiscovered, domain.MediaStatusProbing, domain.MediaStatusThumbnailing,
		domain.MediaStatusReady, domain.MediaStatusFailed,
	}
	for index := range statuses {
		name := fmt.Sprintf("media-%d.mp4", index)
		file := domain.DiscoveredFile{
			RelativePath: name, Filename: name, MediaType: domain.MediaTypeVideo,
			Size: int64(index + 1), ModifiedAt: now,
		}
		result, err := scans.ReconcileFile(context.Background(), job.ID, source.ID,
			fmt.Sprintf("media_%d", index), file, now)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := scans.db.Exec(`UPDATE media_items SET status = ? WHERE id = ?`, statuses[index], result.MediaID); err != nil {
			t.Fatal(err)
		}
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}
	got, err := scans.GetJob(context.Background(), job.ID)
	if err != nil {
		t.Fatal(err)
	}
	summary := got.Processing
	if summary.Status != "running" || summary.Total != 5 || summary.Discovered != 1 ||
		summary.Probing != 1 || summary.Thumbnailing != 1 || summary.Ready != 1 || summary.Failed != 1 {
		t.Fatalf("processing summary = %#v", summary)
	}
	if _, err := scans.db.Exec(`UPDATE media_items SET status = 'ready'
		WHERE last_seen_scan_id = ? AND status IN ('discovered', 'probing', 'thumbnailing')`, job.ID); err != nil {
		t.Fatal(err)
	}
	got, err = scans.LatestJob(context.Background(), source.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Processing.Status != "completed_with_errors" || got.Processing.Ready != 4 || got.Processing.Failed != 1 {
		t.Fatalf("terminal processing summary = %#v", got.Processing)
	}
}

func TestProcessingStatus(t *testing.T) {
	tests := []struct {
		// name 是测试场景名称。
		name string
		// scanStatus 是扫描任务状态。
		scanStatus string
		// want 是期望的处理状态。
		want string
		// summary 是用于计算状态的处理汇总。
		summary domain.ProcessingSummary
	}{
		{name: "pending scan", scanStatus: domain.ScanStatusPending, want: "pending"},
		{name: "active", scanStatus: domain.ScanStatusCompleted, want: "running",
			summary: domain.ProcessingSummary{Probing: 1}},
		{name: "completed", scanStatus: domain.ScanStatusCompleted, want: "completed",
			summary: domain.ProcessingSummary{Ready: 1}},
		{name: "errors", scanStatus: domain.ScanStatusCompleted, want: "completed_with_errors",
			summary: domain.ProcessingSummary{Failed: 1}},
		{name: "failed scan processing ended", scanStatus: domain.ScanStatusFailed, want: "completed",
			summary: domain.ProcessingSummary{Ready: 1}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := processingStatus(test.scanStatus, test.summary); got != test.want {
				t.Fatalf("processingStatus() = %q, want %q", got, test.want)
			}
		})
	}
}

func TestScanMetadataRunQueuesOnlyCurrentUnfinishedWorks(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	ctx := context.Background()
	now := time.Unix(300, 0).UTC()
	source := createTestSource(t, sources, now)
	job := createAndClaimScan(t, scans, source.ID, "scan_metadata", now)
	file := domain.DiscoveredFile{RelativePath: "电影/示例.mkv", Filename: "示例.mkv", MediaType: domain.MediaTypeVideo, Size: 1, ModifiedAt: now}
	media, err := scans.ReconcileFile(ctx, job.ID, source.ID, "metadata_media", file, now)
	if err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(ctx, job.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}
	_, err = scans.db.Exec(`INSERT INTO catalog_items(id,source_id,kind,title,sort_title,metadata_status,created_at_ms,updated_at_ms)
		VALUES('pending_item',?,'movie','示例','示例','pending',?,?),
		('ready_item',?,'movie','已完成','已完成','ready',?,?)`, source.ID, now.UnixMilli(), now.UnixMilli(), source.ID, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	_, err = scans.db.Exec(`INSERT INTO catalog_media_links(media_id,catalog_item_id,match_status,confidence,rule_version,media_updated_at_ms,created_at_ms,updated_at_ms)
		VALUES(?, 'pending_item','matched',100,1,?,?,?)`, media.MediaID, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	catalogs, err := NewCatalogRepository(scans.db)
	if err != nil {
		t.Fatal(err)
	}
	count, err := catalogs.QueueMetadataForScan(ctx, job.ID, source.ID, now)
	if err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("queued item count = %d, want 1", count)
	}
	if count, err = catalogs.QueueMetadataForScan(ctx, job.ID, source.ID, now); err != nil || count != 0 {
		t.Fatalf("duplicate scan run = (%d, %v), want (0, nil)", count, err)
	}
	got, err := scans.GetJob(ctx, job.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Metadata.Status != "running" || got.Metadata.Total != 1 || got.Metadata.Pending != 1 {
		t.Fatalf("metadata summary = %#v", got.Metadata)
	}
	if _, err := scans.db.Exec(`UPDATE catalog_items SET metadata_status='ready' WHERE id='pending_item'`); err != nil {
		t.Fatal(err)
	}
	got, err = scans.GetJob(ctx, job.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Metadata.Status != "completed" || got.Metadata.Ready != 1 {
		t.Fatalf("completed metadata summary = %#v", got.Metadata)
	}
}
