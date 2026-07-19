package sqlite

import (
	"context"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestProcessingRecoverRequeuesAndExhaustsRunningJobs(t *testing.T) {
	f := newProcessingFixture(t)
	f.addMedia("retry", domain.MediaStatusProbing)
	f.addMedia("exhausted", domain.MediaStatusThumbnailing)
	_, err := f.db.Exec(`INSERT INTO media_assets(
        id, media_id, asset_type, variant, storage_key, status, generator_version, created_at_ms, updated_at_ms
    ) VALUES ('asset', 'exhausted', 'thumbnail', 'default', 'x.jpg', 'pending', 1, ?, ?)`,
		f.now.UnixMilli(), f.now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	_, err = f.db.Exec(`INSERT INTO jobs(
        id, job_type, entity_id, status, attempt_count, max_attempts, available_at_ms,
        locked_at_ms, locked_by, created_at_ms, updated_at_ms)
    VALUES ('retry_job', 'probe_media', 'retry', 'running', 1, 2, ?, ?, 'old-worker', ?, ?),
           ('exhausted_job', 'generate_thumbnail', 'exhausted', 'running', 2, 2, ?, ?, 'old-worker', ?, ?)`,
		f.now.UnixMilli(), f.now.UnixMilli(), f.now.UnixMilli(), f.now.UnixMilli(),
		f.now.UnixMilli(), f.now.UnixMilli(), f.now.UnixMilli(), f.now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	recoveredAt := f.now.AddDate(0, 0, 1)
	if err := f.repo.Recover(context.Background(), recoveredAt); err != nil {
		t.Fatal(err)
	}
	var retryStatus, exhaustedStatus, mediaStatus, assetStatus string
	var available int64
	var locked any
	if err := f.db.QueryRow(`SELECT status, available_at_ms, locked_by FROM jobs WHERE id = 'retry_job'`).
		Scan(&retryStatus, &available, &locked); err != nil {
		t.Fatal(err)
	}
	if err := f.db.QueryRow(`SELECT j.status, mi.status, ma.status FROM jobs j
        JOIN media_items mi ON mi.id = j.entity_id JOIN media_assets ma ON ma.media_id = mi.id
        WHERE j.id = 'exhausted_job'`).Scan(&exhaustedStatus, &mediaStatus, &assetStatus); err != nil {
		t.Fatal(err)
	}
	if retryStatus != "pending" || available != recoveredAt.UnixMilli() || locked != nil {
		t.Fatalf("requeued state: status=%s available=%d locked=%v", retryStatus, available, locked)
	}
	if exhaustedStatus != "failed" || mediaStatus != domain.MediaStatusFailed || assetStatus != "failed" {
		t.Fatalf("exhausted state: job=%s media=%s asset=%s", exhaustedStatus, mediaStatus, assetStatus)
	}
}

func TestProcessingListOrphansFiltersActiveJobs(t *testing.T) {
	f := newProcessingFixture(t)
	f.addMedia("active", domain.MediaStatusDiscovered)
	f.addMedia("discovered", domain.MediaStatusDiscovered)
	f.addMedia("probing", domain.MediaStatusProbing)
	f.addMedia("thumbnailing", domain.MediaStatusThumbnailing)
	f.addMedia("ready", domain.MediaStatusReady)
	f.addJob("active_job", domain.JobTypeProbe, "active")

	probe, err := f.repo.ListOrphans(context.Background(), domain.JobTypeProbe, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(probe) != 2 || probe[0].ID != "discovered" || probe[1].ID != "probing" {
		t.Fatalf("probe orphans = %#v", probe)
	}
	thumbnail, err := f.repo.ListOrphans(context.Background(), domain.JobTypeThumbnail, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(thumbnail) != 1 || thumbnail[0].ID != "thumbnailing" || thumbnail[0].RootPath != "/media" {
		t.Fatalf("thumbnail orphans = %#v", thumbnail)
	}
	limited, err := f.repo.ListOrphans(context.Background(), domain.JobTypeProbe, 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(limited) != 1 || limited[0].ID != "discovered" {
		t.Fatalf("limited orphans = %#v", limited)
	}
}

func TestProcessingReclaimExpiredOnlyTouchesTimedOutLocks(t *testing.T) {
	f := newProcessingFixture(t)
	f.addMedia("fresh", domain.MediaStatusProbing)
	f.addMedia("stale", domain.MediaStatusProbing)
	lockedFresh := f.now.Add(5 * time.Minute)
	lockedStale := f.now.Add(-15 * time.Minute)
	_, err := f.db.Exec(`INSERT INTO jobs(
        id, job_type, entity_id, status, attempt_count, max_attempts, available_at_ms,
        locked_at_ms, locked_by, created_at_ms, updated_at_ms)
    VALUES ('fresh_job', 'probe_media', 'fresh', 'running', 1, 2, ?, ?, 'worker', ?, ?),
           ('stale_job', 'probe_media', 'stale', 'running', 1, 2, ?, ?, 'worker', ?, ?)`,
		f.now.UnixMilli(), lockedFresh.UnixMilli(), f.now.UnixMilli(), f.now.UnixMilli(),
		f.now.UnixMilli(), lockedStale.UnixMilli(), f.now.UnixMilli(), f.now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	now := f.now.Add(10 * time.Minute)
	if err := f.repo.ReclaimExpired(context.Background(), now, 10*time.Minute); err != nil {
		t.Fatal(err)
	}
	var freshStatus, staleStatus string
	if err := f.db.QueryRow(`SELECT status FROM jobs WHERE id = 'fresh_job'`).Scan(&freshStatus); err != nil {
		t.Fatal(err)
	}
	if err := f.db.QueryRow(`SELECT status FROM jobs WHERE id = 'stale_job'`).Scan(&staleStatus); err != nil {
		t.Fatal(err)
	}
	if freshStatus != "running" || staleStatus != "pending" {
		t.Fatalf("fresh=%s stale=%s", freshStatus, staleStatus)
	}
}

func TestProcessingEnqueueThumbnailCreatesAssetAndJob(t *testing.T) {
	f := newProcessingFixture(t)
	f.addMedia("media", domain.MediaStatusThumbnailing)
	if err := f.repo.EnqueueThumbnail(context.Background(), "thumb_job", "media", "asset", "thumbnails/media/cover.jpg", f.now); err != nil {
		t.Fatal(err)
	}
	var jobStatus, assetStatus, key string
	err := f.db.QueryRow(`SELECT j.status, ma.status, ma.storage_key FROM jobs j
        JOIN media_assets ma ON ma.media_id = j.entity_id WHERE j.id = 'thumb_job'`).
		Scan(&jobStatus, &assetStatus, &key)
	if err != nil {
		t.Fatal(err)
	}
	if jobStatus != "pending" || assetStatus != "pending" || key != "thumbnails/media/cover.jpg" {
		t.Fatalf("job=%s asset=%s key=%s", jobStatus, assetStatus, key)
	}
}
