package sqlite

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

// newStage2Repositories 创建使用真实迁移的临时 SQLite Repository。
func newStage2Repositories(t *testing.T) (*SourceRepository, *ScanRepository) {
	t.Helper()
	db, err := Open(context.Background(), config.DatabaseConfig{
		Path: filepath.Join(t.TempDir(), "media.db"), BusyTimeoutMS: 1000, WAL: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	sources, err := NewSourceRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	scans, err := NewScanRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	return sources, scans
}

// createTestSource 创建阶段二 Repository 测试使用的媒体源。
func createTestSource(t *testing.T, sources *SourceRepository, now time.Time) domain.Source {
	t.Helper()
	source := domain.Source{
		ID: "source_test", Name: "测试", Type: domain.SourceTypeLocal, RootPath: "/media",
		Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now,
	}
	if err := sources.Create(context.Background(), source); err != nil {
		t.Fatal(err)
	}
	return source
}

// createAndClaimScan 创建并领取一个扫描任务。
func createAndClaimScan(t *testing.T, scans *ScanRepository, sourceID, id string, now time.Time) domain.ScanJob {
	t.Helper()
	job := domain.ScanJob{ID: id, SourceID: sourceID, CreatedAt: now, UpdatedAt: now}
	if err := scans.CreateJob(context.Background(), job); err != nil {
		t.Fatal(err)
	}
	claimed, err := scans.ClaimNextJob(context.Background(), "worker_test", now)
	if err != nil {
		t.Fatal(err)
	}
	return claimed
}

// TestScanRepositoryPreservesMediaIDAcrossRename 验证文件改名后复用稳定媒体 ID。
func TestScanRepositoryPreservesMediaIDAcrossRename(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(100, 0).UTC()
	source := createTestSource(t, sources, now)
	job := createAndClaimScan(t, scans, source.ID, "scan_1", now)
	file := domain.DiscoveredFile{
		RelativePath: "old.mp4", Filename: "old.mp4", MediaType: domain.MediaTypeVideo,
		Size: 10, ModifiedAt: now, FileID: "device:file",
	}
	result, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_1", file, now)
	if err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}

	job = createAndClaimScan(t, scans, source.ID, "scan_2", now.Add(time.Second))
	file.RelativePath, file.Filename = "folder/new.mp4", "new.mp4"
	result, err = scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_2", file, now.Add(time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if result.MediaID != "media_1" || result.Change != "moved" {
		t.Fatalf("改名识别结果错误: %#v", result)
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := scans.db.QueryRow("SELECT COUNT(*) FROM media_items").Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("媒体索引数量 = %d，期望 1", count)
	}
}

// TestFailedScanNeverMarksMediaMissing 验证失败扫描不会批量标记 missing。
func TestFailedScanNeverMarksMediaMissing(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(200, 0).UTC()
	source := createTestSource(t, sources, now)
	job := createAndClaimScan(t, scans, source.ID, "scan_success", now)
	file := domain.DiscoveredFile{
		RelativePath: "keep.jpg", Filename: "keep.jpg", MediaType: domain.MediaTypeImage,
		Size: 5, ModifiedAt: now, QuickHash: "hash",
	}
	if _, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_keep", file, now); err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}
	job = createAndClaimScan(t, scans, source.ID, "scan_failed", now.Add(time.Second))
	if err := scans.FinishJobWithoutCommit(context.Background(), job.ID, domain.ScanStatusFailed, "SCAN_FAILED", "失败", now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	var status string
	if err := scans.db.QueryRow("SELECT status FROM media_items WHERE id = 'media_keep'").Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status == "missing" {
		t.Fatal("失败扫描不得标记媒体 missing")
	}
}

// TestScanRepositoryRejectsConcurrentActiveScan 验证同一媒体源只能存在一个活跃扫描。
func TestScanRepositoryRejectsConcurrentActiveScan(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(300, 0).UTC()
	source := createTestSource(t, sources, now)
	first := domain.ScanJob{ID: "scan_first", SourceID: source.ID, CreatedAt: now, UpdatedAt: now}
	second := domain.ScanJob{ID: "scan_second", SourceID: source.ID, CreatedAt: now, UpdatedAt: now}
	if err := scans.CreateJob(context.Background(), first); err != nil {
		t.Fatal(err)
	}
	if err := scans.CreateJob(context.Background(), second); !errors.Is(err, domain.ErrScanAlreadyRunning) {
		t.Fatalf("错误 = %v，期望 SCAN_ALREADY_RUNNING", err)
	}
}

// TestScanRepositoryUsesQuickHashAndKeepsUserData 验证无 File ID 改名和 missing 用户数据保留。
func TestScanRepositoryUsesQuickHashAndKeepsUserData(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(400, 0).UTC()
	source := createTestSource(t, sources, now)
	job := createAndClaimScan(t, scans, source.ID, "scan_hash_1", now)
	file := domain.DiscoveredFile{
		RelativePath: "before.jpg", Filename: "before.jpg", MediaType: domain.MediaTypeImage,
		Size: 8, ModifiedAt: now, QuickHash: "quick-hash",
	}
	if _, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_hash", file, now); err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}
	_, err := scans.db.Exec(`INSERT INTO media_user_data(
        user_id, media_id, favorite, created_at_ms, updated_at_ms
    ) VALUES ('user_local', 'media_hash', 1, ?, ?)`, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}

	job = createAndClaimScan(t, scans, source.ID, "scan_hash_2", now.Add(time.Second))
	file.RelativePath, file.Filename = "after.jpg", "after.jpg"
	result, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_new", file, now.Add(time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if result.MediaID != "media_hash" || result.Change != "moved" {
		t.Fatalf("快速指纹改名识别失败: %#v", result)
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}

	job = createAndClaimScan(t, scans, source.ID, "scan_hash_3", now.Add(2*time.Second))
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now.Add(2*time.Second)); err != nil {
		t.Fatal(err)
	}
	var status string
	var favorite int
	if err := scans.db.QueryRow(`SELECT mi.status, mud.favorite FROM media_items mi
        JOIN media_user_data mud ON mud.media_id = mi.id WHERE mi.id = 'media_hash'`).Scan(&status, &favorite); err != nil {
		t.Fatal(err)
	}
	if status != "missing" || favorite != 1 {
		t.Fatalf("missing 或用户数据保留错误: status=%s favorite=%d", status, favorite)
	}
}

// TestSourceSoftDeleteReleasesRootPath 验证软删除后可重建相同根路径。
func TestSourceSoftDeleteReleasesRootPath(t *testing.T) {
	sources, _ := newStage2Repositories(t)
	now := time.Unix(500, 0).UTC()
	first := domain.Source{
		ID: "source_old", Name: "旧源", Type: domain.SourceTypeLocal, RootPath: "/media/library",
		Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now,
	}
	if err := sources.Create(context.Background(), first); err != nil {
		t.Fatal(err)
	}
	if err := sources.SoftDelete(context.Background(), first.ID, now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	second := domain.Source{
		ID: "source_new", Name: "新源", Type: domain.SourceTypeLocal, RootPath: "/media/library",
		Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now.Add(2 * time.Second), UpdatedAt: now.Add(2 * time.Second),
	}
	if err := sources.Create(context.Background(), second); err != nil {
		t.Fatalf("软删除后应可重建同路径: %v", err)
	}
	if _, err := sources.Get(context.Background(), first.ID); !errors.Is(err, domain.ErrSourceNotFound) {
		t.Fatalf("已删除媒体源仍可读取: %v", err)
	}
}

// TestReconcileDisplacesConflictingPathIdentity 验证路径命中但 FileID 冲突时不覆盖旧身份。
func TestReconcileDisplacesConflictingPathIdentity(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(600, 0).UTC()
	source := createTestSource(t, sources, now)
	job := createAndClaimScan(t, scans, source.ID, "scan_conflict_1", now)
	oldFile := domain.DiscoveredFile{
		RelativePath: "clip.mp4", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		Size: 10, ModifiedAt: now, FileID: "file-a",
	}
	if _, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_a", oldFile, now); err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}

	job = createAndClaimScan(t, scans, source.ID, "scan_conflict_2", now.Add(time.Second))
	// 旧文件改名离开，新文件占用原路径。
	movedOld := oldFile
	movedOld.RelativePath, movedOld.Filename = "archive/clip.mp4", "clip.mp4"
	if _, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_unused", movedOld, now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	newFile := domain.DiscoveredFile{
		RelativePath: "clip.mp4", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		Size: 20, ModifiedAt: now.Add(time.Second), FileID: "file-b",
	}
	result, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_b", newFile, now.Add(time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if result.MediaID != "media_b" || result.Change != "created" {
		t.Fatalf("新文件应新建索引: %#v", result)
	}
	var pathA, pathB string
	if err := scans.db.QueryRow(`SELECT relative_path FROM media_items WHERE id = 'media_a'`).Scan(&pathA); err != nil {
		t.Fatal(err)
	}
	if err := scans.db.QueryRow(`SELECT relative_path FROM media_items WHERE id = 'media_b'`).Scan(&pathB); err != nil {
		t.Fatal(err)
	}
	if pathA != "archive/clip.mp4" || pathB != "clip.mp4" {
		t.Fatalf("路径分配错误: a=%s b=%s", pathA, pathB)
	}
}

// TestInterruptRunningJobsAlignsStatus 验证启动恢复只中断 running，并且不提交 missing。
func TestInterruptRunningJobsAlignsStatus(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(700, 0).UTC()
	source := createTestSource(t, sources, now)
	seed := createAndClaimScan(t, scans, source.ID, "scan_seed", now)
	file := domain.DiscoveredFile{
		RelativePath: "keep.mp4", Filename: "keep.mp4", MediaType: domain.MediaTypeVideo,
		Size: 10, ModifiedAt: now, FileID: "keep-file",
	}
	if _, err := scans.ReconcileFile(context.Background(), seed.ID, source.ID, "media_keep", file, now); err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), seed.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}
	_ = createAndClaimScan(t, scans, source.ID, "scan_interrupt", now)
	pendingSource := domain.Source{
		ID: "source_pending", Name: "等待扫描", Type: domain.SourceTypeLocal, RootPath: "/pending",
		Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now,
	}
	if err := sources.Create(context.Background(), pendingSource); err != nil {
		t.Fatal(err)
	}
	if err := scans.CreateJob(context.Background(), domain.ScanJob{
		ID: "scan_pending", SourceID: pendingSource.ID, CreatedAt: now, UpdatedAt: now,
	}); err != nil {
		t.Fatal(err)
	}
	if err := scans.InterruptRunningJobs(context.Background(), now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	job, err := scans.GetJob(context.Background(), "scan_interrupt")
	if err != nil {
		t.Fatal(err)
	}
	if job.Status != domain.ScanStatusInterrupted {
		t.Fatalf("scan_jobs.status = %s", job.Status)
	}
	var jobsStatus string
	if err := scans.db.QueryRow(`SELECT status FROM jobs WHERE id = 'scan_interrupt'`).Scan(&jobsStatus); err != nil {
		t.Fatal(err)
	}
	if jobsStatus != domain.ScanStatusInterrupted {
		t.Fatalf("jobs.status = %s", jobsStatus)
	}
	pending, err := scans.GetJob(context.Background(), "scan_pending")
	if err != nil {
		t.Fatal(err)
	}
	if pending.Status != domain.ScanStatusPending {
		t.Fatalf("pending scan status = %s", pending.Status)
	}
	claimed, err := scans.ClaimNextJob(context.Background(), "worker_after_recovery", now.Add(time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if claimed.ID != "scan_pending" {
		t.Fatalf("claimed scan = %s", claimed.ID)
	}
	var mediaStatus string
	if err := scans.db.QueryRow(`SELECT status FROM media_items WHERE id = 'media_keep'`).Scan(&mediaStatus); err != nil {
		t.Fatal(err)
	}
	if mediaStatus == domain.MediaStatusMissing {
		t.Fatal("interrupted scan must not mark media missing")
	}
}

func TestInterruptRunningJobsRejectsInconsistentStatuses(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(750, 0).UTC()
	source := createTestSource(t, sources, now)
	_ = createAndClaimScan(t, scans, source.ID, "scan_inconsistent", now)
	if _, err := scans.db.Exec(`UPDATE scan_jobs SET status = 'pending' WHERE id = 'scan_inconsistent'`); err != nil {
		t.Fatal(err)
	}
	if err := scans.InterruptRunningJobs(context.Background(), now.Add(time.Second)); err == nil {
		t.Fatal("expected inconsistent status error")
	}
	var jobsStatus, scanStatus string
	if err := scans.db.QueryRow(`SELECT status FROM jobs WHERE id = 'scan_inconsistent'`).Scan(&jobsStatus); err != nil {
		t.Fatal(err)
	}
	if err := scans.db.QueryRow(`SELECT status FROM scan_jobs WHERE id = 'scan_inconsistent'`).Scan(&scanStatus); err != nil {
		t.Fatal(err)
	}
	if jobsStatus != domain.ScanStatusRunning || scanStatus != domain.ScanStatusPending {
		t.Fatalf("recovery mutated inconsistent rows: jobs=%s scan_jobs=%s", jobsStatus, scanStatus)
	}
}

// TestMarkFileFailedKeepsLastSeen 验证单文件失败不会在成功收尾时被标 missing。
func TestMarkFileFailedKeepsLastSeen(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(800, 0).UTC()
	source := createTestSource(t, sources, now)
	job := createAndClaimScan(t, scans, source.ID, "scan_keep", now)
	file := domain.DiscoveredFile{
		RelativePath: "keep.mp4", Filename: "keep.mp4", MediaType: domain.MediaTypeVideo,
		Size: 3, ModifiedAt: now, FileID: "keep-id",
	}
	if _, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_keep", file, now); err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}

	job = createAndClaimScan(t, scans, source.ID, "scan_partial", now.Add(time.Second))
	if err := scans.MarkFileFailed(context.Background(), job.ID, source.ID, file, now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	var status string
	if err := scans.db.QueryRow(`SELECT status FROM media_items WHERE id = 'media_keep'`).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status == "missing" {
		t.Fatal("单文件失败后不应标记 missing")
	}
	var sourceStatus string
	if err := scans.db.QueryRow(`SELECT status FROM sources WHERE id = ?`, source.ID).Scan(&sourceStatus); err != nil {
		t.Fatal(err)
	}
	if sourceStatus != domain.SourceStatusDegraded {
		t.Fatalf("部分失败后源状态 = %s", sourceStatus)
	}
}

// TestFailedMediaNeedsProbeOnRescan 验证处理失败的媒体在内容未变时重扫仍会重新探测。
func TestFailedMediaNeedsProbeOnRescan(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(900, 0).UTC()
	source := createTestSource(t, sources, now)
	job := createAndClaimScan(t, scans, source.ID, "scan_create", now)
	file := domain.DiscoveredFile{
		RelativePath: "clip.mp4", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		Size: 42, ModifiedAt: now, FileID: "clip-id",
	}
	result, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_fail", file, now)
	if err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), job.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}
	_, err = scans.db.Exec(`UPDATE media_items SET status = 'failed', error_code = 'PROBE_FAILED' WHERE id = ?`, result.MediaID)
	if err != nil {
		t.Fatal(err)
	}
	job = createAndClaimScan(t, scans, source.ID, "scan_retry", now.Add(time.Second))
	result, err = scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_unused", file, now.Add(time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if !result.NeedsProbe || result.MediaID != "media_fail" {
		t.Fatalf("failed rescan result = %#v", result)
	}
	var status string
	if err := scans.db.QueryRow(`SELECT status FROM media_items WHERE id = 'media_fail'`).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status != domain.MediaStatusDiscovered {
		t.Fatalf("status = %s, want discovered", status)
	}
}

// TestReconcileStoresFileCreatedAt 验证扫描写入并在身份复用时刷新磁盘创建时间。
func TestReconcileStoresFileCreatedAt(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	now := time.Unix(1000, 0).UTC()
	source := createTestSource(t, sources, now)
	job := createAndClaimScan(t, scans, source.ID, "scan_created", now)
	created := time.Date(2026, 8, 20, 8, 0, 0, 0, time.UTC)
	file := domain.DiscoveredFile{
		RelativePath: "clip.mp4", Filename: "clip.mp4", MediaType: domain.MediaTypeVideo,
		Size: 10, ModifiedAt: now, CreatedAt: &created, FileID: "clip-id",
	}
	if _, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_created", file, now); err != nil {
		t.Fatal(err)
	}
	var stored int64
	if err := scans.db.QueryRow(`SELECT file_created_at_ms FROM media_items WHERE id = 'media_created'`).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored != created.UnixMilli() {
		t.Fatalf("file_created_at_ms = %d, want %d", stored, created.UnixMilli())
	}
	later := created.Add(time.Hour)
	file.CreatedAt = &later
	if _, err := scans.ReconcileFile(context.Background(), job.ID, source.ID, "media_unused", file, now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	if err := scans.db.QueryRow(`SELECT file_created_at_ms FROM media_items WHERE id = 'media_created'`).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored != later.UnixMilli() {
		t.Fatalf("updated file_created_at_ms = %d, want %d", stored, later.UnixMilli())
	}
}

// TestReconcileDoesNotResurrectDeletedImage 覆盖删除复活窗口：
// 扫描已读取文件快照（DiscoveredFile 携带旧 mtime/size）→ 用户完成 DELETE
// （文件已删+媒体行+任务）→ 过期快照走到 ReconcileFile 必须被墓碑拦截，
// 不插入新行、不投递 probe，media_items 保持空表。
func TestReconcileDoesNotResurrectDeletedImage(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	db := scans.db
	media, err := NewMediaRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	access, err := NewAccessRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1000, 0).UTC()
	source := createTestSource(t, sources, now)
	if err := access.GrantSource(context.Background(), "user_local", source.ID, now); err != nil {
		t.Fatal(err)
	}
	// 1. 文件已索引，模拟此前一次正常扫描完成。
	file := domain.DiscoveredFile{
		RelativePath: "photos/a.png", Filename: "a.png", MediaType: domain.MediaTypeImage,
		Size: 42, ModifiedAt: now, FileID: "fid-a",
	}
	first := createAndClaimScan(t, scans, source.ID, "scan_1", now)
	if _, err := scans.ReconcileFile(context.Background(), first.ID, source.ID, "media_img", file, now); err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), first.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}
	// 2. 新一轮扫描进行中且已枚举到同一文件快照（与磁盘一致的旧 mtime/size）。
	second := createAndClaimScan(t, scans, source.ID, "scan_2", now.Add(time.Second))
	// 3. 用户在扫描途中永久删除该图片：行被移除，墓碑写入。
	target, err := media.GetImageDeleteTarget(context.Background(), "media_img", "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if err := media.DeleteImageRecord(context.Background(), target, now.Add(2*time.Second)); err != nil {
		t.Fatal(err)
	}
	// 4. 过期快照继续 reconcile：不得复活任何媒体行。
	result, err := scans.ReconcileFile(context.Background(), second.ID, source.ID, "media_new", file, now.Add(2*time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if result.NeedsProbe || result.MediaID != "" {
		t.Fatalf("过期快照不应投递媒体: %#v", result)
	}
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM media_items`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 0 {
		t.Fatalf("删除后媒体索引复活: %d 行", count)
	}
	var jobs int
	if err := db.QueryRow(`SELECT COUNT(*) FROM jobs WHERE job_type = 'probe_media'`).Scan(&jobs); err != nil {
		t.Fatal(err)
	}
	if jobs != 0 {
		t.Fatalf("过期快照投递了 probe 任务: %d", jobs)
	}
	if err := scans.CompleteJob(context.Background(), second.ID, source.ID, now.Add(3*time.Second)); err != nil {
		t.Fatal(err)
	}
}

// TestReconcileAcceptsIdenticalFileAfterDelete 验证删除后新启动的扫描
// 即使发现 mtime/size 与被删文件完全相同的同名文件也正常入库并清掉墓碑：
// 墓碑只拦截删除前已启动的旧扫描快照，不阻止真实重建的相同内容。
func TestReconcileAcceptsIdenticalFileAfterDelete(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	db := scans.db
	media, err := NewMediaRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	access, err := NewAccessRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1000, 0).UTC()
	source := createTestSource(t, sources, now)
	if err := access.GrantSource(context.Background(), "user_local", source.ID, now); err != nil {
		t.Fatal(err)
	}
	file := domain.DiscoveredFile{
		RelativePath: "photos/a.png", Filename: "a.png", MediaType: domain.MediaTypeImage,
		Size: 42, ModifiedAt: now, FileID: "fid-a",
	}
	first := createAndClaimScan(t, scans, source.ID, "scan_1", now)
	if _, err := scans.ReconcileFile(context.Background(), first.ID, source.ID, "media_img", file, now); err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), first.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}
	target, err := media.GetImageDeleteTarget(context.Background(), "media_img", "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if err := media.DeleteImageRecord(context.Background(), target, now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	// 删除后放回一个 mtime/size 完全相同的同名文件；新扫描仍应入库。
	second := createAndClaimScan(t, scans, source.ID, "scan_2", now.Add(2*time.Second))
	result, err := scans.ReconcileFile(context.Background(), second.ID, source.ID, "media_new", file, now.Add(2*time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if !result.NeedsProbe || result.MediaID != "media_new" {
		t.Fatalf("删除后相同文件未被新扫描入库: %#v", result)
	}
	var tombstones int
	if err := db.QueryRow(`SELECT COUNT(*) FROM media_delete_tombstones WHERE source_id = ?`, source.ID).Scan(&tombstones); err != nil {
		t.Fatal(err)
	}
	if tombstones != 0 {
		t.Fatalf("新扫描通过后墓碑未清理: %d", tombstones)
	}
}

// TestOldScanCannotOverwriteUploadedImage 验证旧扫描的迟到快照既不能复活已删文件，
// 也不能覆盖删除后新上传的同名索引行：上传经 IndexUpload 绕过墓碑正常入库并保留墓碑，
// 随后旧扫描的同路径回包按过期水位被拒，新记录不受触碰。
func TestOldScanCannotOverwriteUploadedImage(t *testing.T) {
	sources, scans := newStage2Repositories(t)
	db := scans.db
	media, err := NewMediaRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	access, err := NewAccessRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1000, 0).UTC()
	source := createTestSource(t, sources, now)
	if err := access.GrantSource(context.Background(), "user_local", source.ID, now); err != nil {
		t.Fatal(err)
	}
	file := domain.DiscoveredFile{
		RelativePath: "a.png", Filename: "a.png", MediaType: domain.MediaTypeImage,
		Size: 42, ModifiedAt: now, FileID: "fid-a",
	}
	first := createAndClaimScan(t, scans, source.ID, "scan_1", now)
	if _, err := scans.ReconcileFile(context.Background(), first.ID, source.ID, "media_img", file, now); err != nil {
		t.Fatal(err)
	}
	if err := scans.CompleteJob(context.Background(), first.ID, source.ID, now); err != nil {
		t.Fatal(err)
	}
	// 旧扫描在删除前已启动并枚举了旧文件快照。
	second := createAndClaimScan(t, scans, source.ID, "scan_2", now.Add(time.Second))
	target, err := media.GetImageDeleteTarget(context.Background(), "media_img", "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if err := media.DeleteImageRecord(context.Background(), target, now.Add(2*time.Second)); err != nil {
		t.Fatal(err)
	}
	// 同名重新上传：IndexUpload 绕过墓碑，新文件获得全新 media_id 并落索引。
	uploaded := domain.DiscoveredFile{
		RelativePath: "a.png", Filename: "a.png", MediaType: domain.MediaTypeImage,
		Size: 77, ModifiedAt: now.Add(3 * time.Second), FileID: "fid-new",
	}
	up, err := scans.IndexUpload(context.Background(), source.ID, "media_reup", uploaded, now.Add(3*time.Second), "job_probe_reup")
	if err != nil {
		t.Fatal(err)
	}
	if up.MediaID != "media_reup" || !up.NeedsProbe {
		t.Fatalf("重新上传未正常入库: %#v", up)
	}
	// 墓碑仍然保留，旧扫描迟到回包必须被拒且不触碰新记录。
	var tombstones int
	if err := db.QueryRow(`SELECT COUNT(*) FROM media_delete_tombstones WHERE source_id = ?`, source.ID).Scan(&tombstones); err != nil {
		t.Fatal(err)
	}
	if tombstones != 1 {
		t.Fatalf("上传不应清除墓碑: %d", tombstones)
	}
	result, err := scans.ReconcileFile(context.Background(), second.ID, source.ID, "media_stale", file, now.Add(4*time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if result.MediaID != "" || result.NeedsProbe {
		t.Fatalf("旧扫描回包不应入库: %#v", result)
	}
	// 新上传记录的相对路径、file_id 未被旧快照覆盖。
	var relPath, fid string
	if err := db.QueryRow(`SELECT relative_path, COALESCE(file_id,'') FROM media_items WHERE id = 'media_reup'`).Scan(&relPath, &fid); err != nil {
		t.Fatal(err)
	}
	if relPath != "a.png" || fid != "fid-new" {
		t.Fatalf("旧扫描覆盖了新上传记录: %q %q", relPath, fid)
	}
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM media_items`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("媒体索引应有且仅有新上传行: %d", count)
	}
}
