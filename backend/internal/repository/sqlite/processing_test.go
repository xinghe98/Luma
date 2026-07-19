package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

type processingFixture struct {
	// t 是当前测试实例。
	t *testing.T
	// db 是测试使用的数据库连接。
	db *sql.DB
	// repo 是待测试的处理仓储。
	repo *ProcessingRepository
	// now 是测试使用的固定时间。
	now time.Time
}

func newProcessingFixture(t *testing.T) processingFixture {
	t.Helper()
	db, err := Open(context.Background(), config.DatabaseConfig{
		Path: filepath.Join(t.TempDir(), "processing.db"), BusyTimeoutMS: 1000, WAL: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	repo, err := NewProcessingRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Unix(1000, 0).UTC()
	_, err = db.Exec(`INSERT INTO sources(
        id, name, source_type, root_path, enabled, status, created_at_ms, updated_at_ms
    ) VALUES ('source', 'test', 'local', '/media', 1, 'online', ?, ?)`, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	return processingFixture{t: t, db: db, repo: repo, now: now}
}

func (f processingFixture) addMedia(id, status string) domain.MediaInput {
	f.t.Helper()
	modified := f.now.Add(-time.Minute).UnixMilli()
	_, err := f.db.Exec(`INSERT INTO media_items(
        id, source_id, relative_path, filename, media_type, file_size, file_modified_at_ms,
        status, discovered_at_ms, created_at_ms, updated_at_ms
    ) VALUES (?, 'source', ?, ?, 'video', 42, ?, ?, ?, ?, ?)`,
		id, id+".mp4", id+".mp4", modified, status, f.now.UnixMilli(), f.now.UnixMilli(), f.now.UnixMilli())
	if err != nil {
		f.t.Fatal(err)
	}
	return domain.MediaInput{ID: id, SourceID: "source", RootPath: "/media", RelativePath: id + ".mp4",
		MediaType: domain.MediaTypeVideo, FileSize: 42, ModifiedAtMS: modified}
}

func (f processingFixture) addJob(id, kind, mediaID string) {
	f.t.Helper()
	_, err := f.db.Exec(`INSERT INTO jobs(
        id, job_type, entity_id, status, max_attempts, available_at_ms, created_at_ms, updated_at_ms
    ) VALUES (?, ?, ?, 'pending', 2, ?, ?, ?)`, id, kind, mediaID,
		f.now.UnixMilli(), f.now.UnixMilli(), f.now.UnixMilli())
	if err != nil {
		f.t.Fatal(err)
	}
}

func TestProcessingEnqueueAndClaimUpdatesAttemptAndStatus(t *testing.T) {
	f := newProcessingFixture(t)
	f.addMedia("media", domain.MediaStatusDiscovered)
	if err := f.repo.EnqueueProbe(context.Background(), "probe", "media", f.now); err != nil {
		t.Fatal(err)
	}
	job, err := f.repo.Claim(context.Background(), domain.JobTypeProbe, "worker", f.now)
	if err != nil {
		t.Fatal(err)
	}
	if job.ID != "probe" || job.Attempt != 1 || job.MaxAttempts != 2 {
		t.Fatalf("claimed job = %#v", job)
	}
	var jobStatus, mediaStatus, lockedBy string
	var attempts int
	if err := f.db.QueryRow(`SELECT j.status, j.attempt_count, j.locked_by, mi.status
        FROM jobs j JOIN media_items mi ON mi.id = j.entity_id WHERE j.id = 'probe'`).
		Scan(&jobStatus, &attempts, &lockedBy, &mediaStatus); err != nil {
		t.Fatal(err)
	}
	if jobStatus != "running" || attempts != 1 || lockedBy != "worker" || mediaStatus != domain.MediaStatusProbing {
		t.Fatalf("status: job=%s attempts=%d worker=%s media=%s", jobStatus, attempts, lockedBy, mediaStatus)
	}
}

func TestProcessingCompleteProbeCommitsMetadataAssetAndJob(t *testing.T) {
	f := newProcessingFixture(t)
	media := f.addMedia("media", domain.MediaStatusDiscovered)
	if err := f.repo.EnqueueProbe(context.Background(), "probe", media.ID, f.now); err != nil {
		t.Fatal(err)
	}
	job, err := f.repo.Claim(context.Background(), domain.JobTypeProbe, "worker", f.now)
	if err != nil {
		t.Fatal(err)
	}
	duration, width := int64(9000), 1920
	probe := domain.ProbeResult{Title: "Title", MIMEType: "video/mp4", DurationMS: &duration,
		Width: &width, RawJSON: []byte(`{"format":"mp4"}`), Version: 3}
	matched, err := f.repo.CompleteProbe(context.Background(), job, media, probe,
		"asset", "thumbnail", "thumb/media.jpg", f.now.Add(time.Second))
	if err != nil || !matched {
		t.Fatalf("matched=%v err=%v", matched, err)
	}
	var title, mime, mediaStatus, raw, assetStatus, key, probeStatus, thumbnailStatus string
	var gotDuration int64
	var gotWidth, version int
	err = f.db.QueryRow(`SELECT mi.detected_title, mi.mime_type, mi.duration_ms, mi.width, mi.status,
        mi.probe_data, mi.probe_version, ma.status, ma.storage_key, pj.status, tj.status
        FROM media_items mi JOIN media_assets ma ON ma.media_id = mi.id
        JOIN jobs pj ON pj.id = 'probe' JOIN jobs tj ON tj.id = 'thumbnail' WHERE mi.id = 'media'`).
		Scan(&title, &mime, &gotDuration, &gotWidth, &mediaStatus, &raw, &version,
			&assetStatus, &key, &probeStatus, &thumbnailStatus)
	if err != nil {
		t.Fatal(err)
	}
	if title != "Title" || mime != "video/mp4" || gotDuration != duration || gotWidth != width || version != 3 || raw != string(probe.RawJSON) || mediaStatus != domain.MediaStatusThumbnailing || assetStatus != "pending" || key != "thumb/media.jpg" || probeStatus != "completed" || thumbnailStatus != "pending" {
		t.Fatalf("unexpected committed state: title=%s media=%s asset=%s probe=%s thumbnail=%s", title, mediaStatus, assetStatus, probeStatus, thumbnailStatus)
	}
}
