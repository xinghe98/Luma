package sqlite

import (
	"context"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func prepareThumbnail(t *testing.T, f processingFixture, media domain.MediaInput) domain.ProcessingJob {
	t.Helper()
	f.addJob("thumbnail", domain.JobTypeThumbnail, media.ID)
	_, err := f.db.Exec(`INSERT INTO media_assets(
        id, media_id, asset_type, variant, storage_key, status, generator_version, created_at_ms, updated_at_ms
    ) VALUES ('asset', ?, 'thumbnail', 'default', 'pending.jpg', 'pending', 1, ?, ?)`,
		media.ID, f.now.UnixMilli(), f.now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	job, err := f.repo.Claim(context.Background(), domain.JobTypeThumbnail, "worker", f.now)
	if err != nil {
		t.Fatal(err)
	}
	return job
}

func TestProcessingCompleteThumbnailMarksAssetAndMediaReady(t *testing.T) {
	f := newProcessingFixture(t)
	media := f.addMedia("media", domain.MediaStatusThumbnailing)
	job := prepareThumbnail(t, f, media)
	result := domain.ThumbnailResult{StorageKey: "ready.jpg", MIMEType: "image/jpeg", ContentSHA256: "deadbeef", Width: 320, Height: 180}
	matched, err := f.repo.CompleteThumbnail(context.Background(), job, media, result, f.now.Add(time.Second))
	if err != nil || !matched {
		t.Fatalf("matched=%v err=%v", matched, err)
	}
	var mediaStatus, assetStatus, key, mime, hash, jobStatus string
	var width, height int
	var indexed int64
	err = f.db.QueryRow(`SELECT mi.status, mi.indexed_at_ms, ma.status, ma.storage_key,
        ma.mime_type, COALESCE(ma.content_sha256, ''), ma.width, ma.height, j.status FROM media_items mi
        JOIN media_assets ma ON ma.media_id = mi.id JOIN jobs j ON j.id = 'thumbnail'
        WHERE mi.id = 'media'`).Scan(&mediaStatus, &indexed, &assetStatus, &key, &mime, &hash, &width, &height, &jobStatus)
	if err != nil {
		t.Fatal(err)
	}
	if mediaStatus != domain.MediaStatusReady || indexed != f.now.Add(time.Second).UnixMilli() || assetStatus != "ready" || key != "ready.jpg" || mime != "image/jpeg" || hash != "deadbeef" || width != 320 || height != 180 || jobStatus != "completed" {
		t.Fatalf("ready state: media=%s asset=%s key=%s hash=%s job=%s", mediaStatus, assetStatus, key, hash, jobStatus)
	}
}

func TestProcessingCompleteProbeKeepsReadyThumbnail(t *testing.T) {
	f := newProcessingFixture(t)
	media := f.addMedia("media", domain.MediaStatusReady)
	_, err := f.db.Exec(`INSERT INTO media_assets(
        id, media_id, asset_type, variant, storage_key, status, content_sha256, generator_version, created_at_ms, updated_at_ms
    ) VALUES ('asset', 'media', 'thumbnail', 'default', 'ready.jpg', 'ready', 'oldhash', 1, ?, ?)`,
		f.now.UnixMilli(), f.now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	if err := f.repo.EnqueueProbe(context.Background(), "probe", media.ID, f.now); err != nil {
		t.Fatal(err)
	}
	job, err := f.repo.Claim(context.Background(), domain.JobTypeProbe, "worker", f.now)
	if err != nil {
		t.Fatal(err)
	}
	duration, width := int64(12000), 1280
	matched, err := f.repo.CompleteProbe(context.Background(), job, media,
		domain.ProbeResult{Title: "Again", MIMEType: "video/mp4", DurationMS: &duration, Width: &width, Version: 2, RawJSON: []byte(`{}`)},
		"asset", "thumbnail_re", "ready.jpg", f.now.Add(time.Second))
	if err != nil || !matched {
		t.Fatalf("matched=%v err=%v", matched, err)
	}
	var assetStatus, key, mediaStatus, thumbJob string
	err = f.db.QueryRow(`SELECT ma.status, ma.storage_key, mi.status, tj.status FROM media_assets ma
        JOIN media_items mi ON mi.id = ma.media_id JOIN jobs tj ON tj.id = 'thumbnail_re'
        WHERE ma.media_id = 'media'`).Scan(&assetStatus, &key, &mediaStatus, &thumbJob)
	if err != nil {
		t.Fatal(err)
	}
	if assetStatus != "ready" || key != "ready.jpg" || mediaStatus != domain.MediaStatusThumbnailing || thumbJob != "pending" {
		t.Fatalf("asset=%s key=%s media=%s thumbJob=%s", assetStatus, key, mediaStatus, thumbJob)
	}
}

func TestProcessingVersionMismatchDoesNotOverwriteMedia(t *testing.T) {
	f := newProcessingFixture(t)
	media := f.addMedia("media", domain.MediaStatusDiscovered)
	if err := f.repo.EnqueueProbe(context.Background(), "probe", media.ID, f.now); err != nil {
		t.Fatal(err)
	}
	job, err := f.repo.Claim(context.Background(), domain.JobTypeProbe, "worker", f.now)
	if err != nil {
		t.Fatal(err)
	}
	_, err = f.db.Exec(`UPDATE media_items SET file_size = 99, status = 'discovered',
        detected_title = 'newer title' WHERE id = 'media'`)
	if err != nil {
		t.Fatal(err)
	}
	matched, err := f.repo.CompleteProbe(context.Background(), job, media,
		domain.ProbeResult{Title: "stale title", Version: 9}, "asset", "thumbnail", "stale.jpg", f.now.Add(time.Second))
	if err != nil || matched {
		t.Fatalf("matched=%v err=%v", matched, err)
	}
	var title, status, jobStatus string
	var size int64
	var assets, thumbnailJobs int
	err = f.db.QueryRow(`SELECT detected_title, status, file_size FROM media_items WHERE id = 'media'`).Scan(&title, &status, &size)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.db.QueryRow(`SELECT status FROM jobs WHERE id = 'probe'`).Scan(&jobStatus); err != nil {
		t.Fatal(err)
	}
	if err := f.db.QueryRow(`SELECT COUNT(*) FROM media_assets WHERE media_id = 'media'`).Scan(&assets); err != nil {
		t.Fatal(err)
	}
	if err := f.db.QueryRow(`SELECT COUNT(*) FROM jobs WHERE id = 'thumbnail'`).Scan(&thumbnailJobs); err != nil {
		t.Fatal(err)
	}
	if title != "newer title" || status != domain.MediaStatusDiscovered || size != 99 || assets != 0 || thumbnailJobs != 0 || jobStatus != "cancelled" {
		t.Fatalf("stale completion overwrote state: title=%s status=%s size=%d assets=%d jobs=%d probe=%s", title, status, size, assets, thumbnailJobs, jobStatus)
	}
}

func TestProcessingFailRetriesThenFailsMediaAndAsset(t *testing.T) {
	f := newProcessingFixture(t)
	media := f.addMedia("media", domain.MediaStatusThumbnailing)
	job := prepareThumbnail(t, f, media)
	retry, err := f.repo.Fail(context.Background(), job, "THUMB", "first", f.now)
	if err != nil || !retry {
		t.Fatalf("first fail: retry=%v err=%v", retry, err)
	}
	var status string
	var available int64
	if err := f.db.QueryRow(`SELECT status, available_at_ms FROM jobs WHERE id = 'thumbnail'`).Scan(&status, &available); err != nil {
		t.Fatal(err)
	}
	if status != "pending" || available != f.now.Add(time.Second).UnixMilli() {
		t.Fatalf("retry state: status=%s available=%d", status, available)
	}
	job, err = f.repo.Claim(context.Background(), domain.JobTypeThumbnail, "worker", f.now.Add(time.Second))
	if err != nil || job.Attempt != 2 {
		t.Fatalf("second claim: job=%#v err=%v", job, err)
	}
	retry, err = f.repo.Fail(context.Background(), job, "THUMB", "final", f.now.Add(2*time.Second))
	if err != nil || retry {
		t.Fatalf("final fail: retry=%v err=%v", retry, err)
	}
	var mediaStatus, assetStatus string
	if err := f.db.QueryRow(`SELECT j.status, mi.status, ma.status FROM jobs j
        JOIN media_items mi ON mi.id = j.entity_id JOIN media_assets ma ON ma.media_id = mi.id
        WHERE j.id = 'thumbnail'`).Scan(&status, &mediaStatus, &assetStatus); err != nil {
		t.Fatal(err)
	}
	if status != "failed" || mediaStatus != domain.MediaStatusFailed || assetStatus != "failed" {
		t.Fatalf("final state: job=%s media=%s asset=%s", status, mediaStatus, assetStatus)
	}
}
