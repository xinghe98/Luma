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

func newMediaRepositoryTest(t *testing.T) (*MediaRepository, *SourceRepository) {
	t.Helper()
	db, err := Open(context.Background(), config.DatabaseConfig{Path: filepath.Join(t.TempDir(), "media.db"), BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	media, err := NewMediaRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	sources, err := NewSourceRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	return media, sources
}

func insertMedia(t *testing.T, repository *MediaRepository, id, sourceID, filename, mediaType, status string, discoveredMS int64, duration *int64) {
	t.Helper()
	_, err := repository.db.Exec(`INSERT INTO media_items(
        id,source_id,relative_path,filename,media_type,file_size,file_modified_at_ms,duration_ms,status,
        discovered_at_ms,created_at_ms,updated_at_ms) VALUES(?,?,?,?,?,100,1,?,?,?,?,?)`,
		id, sourceID, id+"/"+filename, filename, mediaType, duration, status, discoveredMS, discoveredMS, discoveredMS)
	if err != nil {
		t.Fatal(err)
	}
}

func TestMediaRepositoryStableCursorAndVisibility(t *testing.T) {
	repository, sources := newMediaRepositoryTest(t)
	now := time.UnixMilli(1000).UTC()
	for _, source := range []domain.Source{
		{ID: "source_on", Name: "启用", Type: domain.SourceTypeLocal, RootPath: "/on", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now},
		{ID: "source_off", Name: "禁用", Type: domain.SourceTypeLocal, RootPath: "/off", Enabled: false, Status: domain.SourceStatusDisabled, CreatedAt: now, UpdatedAt: now},
	} {
		if err := sources.Create(context.Background(), source); err != nil {
			t.Fatal(err)
		}
	}
	for _, id := range []string{"media_a", "media_b", "media_c"} {
		insertMedia(t, repository, id, "source_on", id+".mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 1000, nil)
	}
	insertMedia(t, repository, "media_missing", "source_on", "missing.mp4", domain.MediaTypeVideo, domain.MediaStatusMissing, 1000, nil)
	insertMedia(t, repository, "media_disabled", "source_off", "disabled.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 1000, nil)

	query := domain.MediaListQuery{UserID: "user_local", Sort: domain.MediaSortCreatedAt, Order: domain.SortDescending, Limit: 2}
	first, err := repository.List(context.Background(), query)
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 2 || first[0].ID != "media_c" || first[1].ID != "media_b" {
		t.Fatalf("unexpected first page: %#v", first)
	}
	insertMedia(t, repository, "media_new", "source_on", "new.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 2000, nil)
	query.After = &domain.MediaPageKey{IntValue: first[1].DiscoveredAt.UnixMilli(), ID: first[1].ID}
	second, err := repository.List(context.Background(), query)
	if err != nil {
		t.Fatal(err)
	}
	if len(second) != 1 || second[0].ID != "media_a" {
		t.Fatalf("unexpected second page: %#v", second)
	}
}

func TestMediaRepositoryStreamLocationVisibility(t *testing.T) {
	repository, sources := newMediaRepositoryTest(t)
	now := time.UnixMilli(1000).UTC()
	for _, source := range []domain.Source{
		{ID: "source_on", Name: "启用", Type: domain.SourceTypeLocal, RootPath: "/media", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now},
		{ID: "source_off", Name: "禁用", Type: domain.SourceTypeLocal, RootPath: "/off", Enabled: false, Status: domain.SourceStatusDisabled, CreatedAt: now, UpdatedAt: now},
		{ID: "source_deleted", Name: "删除", Type: domain.SourceTypeLocal, RootPath: "/deleted", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now},
	} {
		if err := sources.Create(context.Background(), source); err != nil {
			t.Fatal(err)
		}
	}
	for _, status := range []string{
		domain.MediaStatusDiscovered, domain.MediaStatusProbing, domain.MediaStatusThumbnailing,
		domain.MediaStatusReady, domain.MediaStatusFailed,
	} {
		insertMedia(t, repository, status, "source_on", status+".mp4", domain.MediaTypeVideo, status, 1000, nil)
		location, err := repository.GetStreamLocation(context.Background(), status)
		if err != nil {
			t.Fatalf("status=%s error=%v", status, err)
		}
		if location.RootPath != "/media" || location.RelativePath != status+"/"+status+".mp4" {
			t.Fatalf("location = %#v", location)
		}
	}
	insertMedia(t, repository, "image", "source_on", "photo.jpg", domain.MediaTypeImage, domain.MediaStatusReady, 1000, nil)
	image, err := repository.GetStreamLocation(context.Background(), "image")
	if err != nil {
		t.Fatal(err)
	}
	if image.MediaType != domain.MediaTypeImage || image.Filename != "photo.jpg" {
		t.Fatalf("image location = %#v", image)
	}
	insertMedia(t, repository, "missing", "source_on", "missing.mp4", domain.MediaTypeVideo, domain.MediaStatusMissing, 1000, nil)
	insertMedia(t, repository, "disabled", "source_off", "disabled.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 1000, nil)
	insertMedia(t, repository, "deleted", "source_deleted", "deleted.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 1000, nil)
	if _, err := repository.db.Exec(`UPDATE sources SET deleted_at_ms=2 WHERE id='source_deleted'`); err != nil {
		t.Fatal(err)
	}
	for _, id := range []string{"missing", "disabled", "deleted", "unknown"} {
		if _, err := repository.GetStreamLocation(context.Background(), id); !errors.Is(err, domain.ErrMediaNotFound) {
			t.Fatalf("id=%s error=%v", id, err)
		}
	}
}

func TestMediaRepositorySearchUserDataAndThumbnail(t *testing.T) {
	repository, sources := newMediaRepositoryTest(t)
	now := time.UnixMilli(1000).UTC()
	source := domain.Source{ID: "source", Name: "源", Type: domain.SourceTypeLocal, RootPath: "/media", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now}
	if err := sources.Create(context.Background(), source); err != nil {
		t.Fatal(err)
	}
	duration := int64(1234)
	insertMedia(t, repository, "media_1", source.ID, "Holiday_100%.MP4", domain.MediaTypeVideo, domain.MediaStatusReady, 1000, &duration)
	_, err := repository.db.Exec(`INSERT INTO media_user_data(user_id,media_id,custom_title,favorite,progress_ms,created_at_ms,updated_at_ms)
        VALUES('user_local','media_1','自定义标题',1,321,1,1)`)
	if err != nil {
		t.Fatal(err)
	}
	_, err = repository.db.Exec(`INSERT INTO media_assets(id,media_id,asset_type,variant,storage_key,mime_type,status,generator_version,created_at_ms,updated_at_ms)
        VALUES('asset_1','media_1','thumbnail','default','thumbnails/media_1/old.jpg','image/jpeg','ready',1,1,1),
              ('asset_2','media_1','thumbnail','default','thumbnails/media_1/new.jpg','image/jpeg','ready',2,2,2)`)
	if err != nil {
		t.Fatal(err)
	}
	items, err := repository.List(context.Background(), domain.MediaListQuery{
		UserID: "user_local", Search: "100%", MediaType: domain.MediaTypeVideo,
		Sort: domain.MediaSortFilename, Order: domain.SortAscending, Limit: 10,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].Title != "自定义标题" || !items[0].Favorite || items[0].ProgressMS != 321 || !items[0].HasThumbnail {
		t.Fatalf("unexpected media: %#v", items)
	}
	asset, err := repository.GetThumbnail(context.Background(), "media_1", domain.ThumbnailVariantDefault)
	if err != nil {
		t.Fatal(err)
	}
	if asset.ID != "asset_2" {
		t.Fatalf("asset = %q", asset.ID)
	}
	if _, err := repository.Get(context.Background(), "unknown", "user_local"); !errors.Is(err, domain.ErrMediaNotFound) {
		t.Fatalf("error = %v", err)
	}
}

func TestMediaRepositoryUserFiltersAndContinueWatching(t *testing.T) {
	repository, sources := newMediaRepositoryTest(t)
	ctx := context.Background()
	now := time.UnixMilli(1000).UTC()
	if err := sources.Create(ctx, domain.Source{ID: "source_filters", Name: "筛选", Type: domain.SourceTypeLocal, RootPath: "/media", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now}); err != nil {
		t.Fatal(err)
	}
	duration := int64(100000)
	for _, item := range []struct {
		id        string
		mediaType string
	}{
		{"video_new", domain.MediaTypeVideo}, {"video_old", domain.MediaTypeVideo},
		{"video_done", domain.MediaTypeVideo}, {"image", domain.MediaTypeImage}, {"untouched", domain.MediaTypeVideo},
		{"zero_progress", domain.MediaTypeVideo},
	} {
		insertMedia(t, repository, item.id, "source_filters", item.id+".mp4", item.mediaType, domain.MediaStatusReady, 1000, &duration)
	}
	if _, err := repository.db.Exec(`INSERT INTO tags(id,user_id,name,normalized_name,created_at_ms,updated_at_ms,revision)
        VALUES('tag_filter','user_local','筛选','筛选',1,1,1)`); err != nil {
		t.Fatal(err)
	}
	for _, row := range []struct {
		id        string
		favorite  int
		progress  int64
		completed int
		played    int64
	}{
		{"video_new", 1, 50000, 0, 3000},
		{"video_old", 0, 40000, 0, 2000},
		{"video_done", 1, 95000, 1, 4000},
		{"image", 1, 1, 0, 5000},
		{"zero_progress", 0, 0, 0, 0},
	} {
		if _, err := repository.db.Exec(`INSERT INTO media_user_data(
            user_id,media_id,favorite,progress_ms,completed,last_played_at_ms,created_at_ms,updated_at_ms,revision
        ) VALUES('user_local',?,?,?,?,?,1,1,1)`, row.id, row.favorite, row.progress, row.completed, row.played); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := repository.db.Exec(`INSERT INTO media_tags(user_id,media_id,tag_id,created_at_ms)
        VALUES('user_local','video_new','tag_filter',1)`); err != nil {
		t.Fatal(err)
	}
	favorite := true
	items, err := repository.List(ctx, domain.MediaListQuery{UserID: "user_local", Favorite: &favorite, Sort: domain.MediaSortCreatedAt, Order: domain.SortDescending, Limit: 20})
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 3 {
		t.Fatalf("favorite items=%#v", items)
	}
	tagged, err := repository.List(ctx, domain.MediaListQuery{UserID: "user_local", TagID: "tag_filter", Sort: domain.MediaSortCreatedAt, Order: domain.SortDescending, Limit: 20})
	if err != nil || len(tagged) != 1 || tagged[0].ID != "video_new" {
		t.Fatalf("tagged=%#v err=%v", tagged, err)
	}
	for _, test := range []struct {
		status string
		ids    map[string]bool
	}{
		{domain.WatchStatusUnwatched, map[string]bool{"untouched": true, "zero_progress": true}},
		{domain.WatchStatusWatching, map[string]bool{"video_new": true, "video_old": true, "image": true}},
		{domain.WatchStatusCompleted, map[string]bool{"video_done": true}},
	} {
		filtered, err := repository.List(ctx, domain.MediaListQuery{
			UserID: "user_local", WatchStatus: test.status,
			Sort: domain.MediaSortCreatedAt, Order: domain.SortDescending, Limit: 20,
		})
		if err != nil || len(filtered) != len(test.ids) {
			t.Fatalf("watch_status=%s items=%#v err=%v", test.status, filtered, err)
		}
		for _, item := range filtered {
			if !test.ids[item.ID] {
				t.Fatalf("watch_status=%s unexpected item=%s", test.status, item.ID)
			}
		}
	}
	watching, err := repository.List(ctx, domain.MediaListQuery{
		UserID: "user_local", MediaType: domain.MediaTypeVideo, ContinueWatching: true,
		Sort: domain.MediaSortLastPlayedAt, Order: domain.SortDescending, Limit: 20,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(watching) != 2 || watching[0].ID != "video_new" || watching[1].ID != "video_old" || watching[0].LastPlayedAt == nil {
		t.Fatalf("watching=%#v", watching)
	}
	after := domain.MediaPageKey{IntValue: watching[0].LastPlayedAt.UnixMilli(), ID: watching[0].ID}
	next, err := repository.List(ctx, domain.MediaListQuery{
		UserID: "user_local", MediaType: domain.MediaTypeVideo, ContinueWatching: true,
		Sort: domain.MediaSortLastPlayedAt, Order: domain.SortDescending, Limit: 20, After: &after,
	})
	if err != nil || len(next) != 1 || next[0].ID != "video_old" {
		t.Fatalf("next=%#v err=%v", next, err)
	}
}

func TestMediaRepositoryStableSortFiltersAndHasThumbnail(t *testing.T) {
	repository, sources := newMediaRepositoryTest(t)
	now := time.UnixMilli(1000).UTC()
	source := domain.Source{ID: "source", Name: "源", Type: domain.SourceTypeLocal, RootPath: "/media", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now}
	if err := sources.Create(context.Background(), source); err != nil {
		t.Fatal(err)
	}
	short, long := int64(10), int64(30)
	insertMedia(t, repository, "media_discovered", source.ID, "new.mp4", domain.MediaTypeVideo, domain.MediaStatusDiscovered, 1, nil)
	insertMedia(t, repository, "media_probing", source.ID, "probe.mp4", domain.MediaTypeVideo, domain.MediaStatusProbing, 2, nil)
	insertMedia(t, repository, "media_thumb", source.ID, "thumb.mp4", domain.MediaTypeVideo, domain.MediaStatusThumbnailing, 3, &short)
	insertMedia(t, repository, "media_ready", source.ID, "ready.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 4, &long)
	insertMedia(t, repository, "media_failed", source.ID, "fail.mp4", domain.MediaTypeVideo, domain.MediaStatusFailed, 5, nil)
	_, err := repository.db.Exec(`INSERT INTO media_assets(id,media_id,asset_type,variant,storage_key,mime_type,status,content_sha256,generator_version,created_at_ms,updated_at_ms)
        VALUES('asset_ready','media_ready','thumbnail','default','thumbnails/media_ready/cover.jpg','image/jpeg','ready','abc',1,1,1)`)
	if err != nil {
		t.Fatal(err)
	}

	durationItems, err := repository.List(context.Background(), domain.MediaListQuery{
		UserID: "user_local", Sort: domain.MediaSortDuration, Order: domain.SortAscending, Limit: 20,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(durationItems) != 3 || durationItems[0].ID != "media_thumb" || durationItems[1].ID != "media_ready" || durationItems[2].ID != "media_failed" {
		t.Fatalf("duration filter = %#v", durationItems)
	}
	if durationItems[1].HasThumbnail != true || durationItems[0].HasThumbnail {
		t.Fatalf("has_thumbnail flags = %#v", durationItems)
	}

	sizeItems, err := repository.List(context.Background(), domain.MediaListQuery{
		UserID: "user_local", Sort: domain.MediaSortFileSize, Order: domain.SortAscending, Limit: 20,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(sizeItems) != 2 {
		t.Fatalf("file_size filter = %#v", sizeItems)
	}
	ids := map[string]bool{sizeItems[0].ID: true, sizeItems[1].ID: true}
	if !ids["media_ready"] || !ids["media_failed"] {
		t.Fatalf("file_size filter = %#v", sizeItems)
	}

	asset, err := repository.GetThumbnail(context.Background(), "media_ready", domain.ThumbnailVariantDefault)
	if err != nil {
		t.Fatal(err)
	}
	if asset.ContentSHA256 != "abc" {
		t.Fatalf("content hash = %q", asset.ContentSHA256)
	}
	detail, err := repository.Get(context.Background(), "media_discovered", "user_local")
	if err != nil || detail.HasThumbnail {
		t.Fatalf("discovered detail = %#v err=%v", detail, err)
	}
}

func TestMediaRepositoryDurationDescNullLastPaging(t *testing.T) {
	repository, sources := newMediaRepositoryTest(t)
	now := time.UnixMilli(1000).UTC()
	source := domain.Source{ID: "source", Name: "源", Type: domain.SourceTypeLocal, RootPath: "/media", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now}
	if err := sources.Create(context.Background(), source); err != nil {
		t.Fatal(err)
	}
	short, long := int64(10), int64(20)
	insertMedia(t, repository, "media_short", source.ID, "short.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 1, &short)
	insertMedia(t, repository, "media_long", source.ID, "long.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 2, &long)
	insertMedia(t, repository, "media_null_b", source.ID, "null-b.mp4", domain.MediaTypeVideo, domain.MediaStatusFailed, 3, nil)
	insertMedia(t, repository, "media_null_a", source.ID, "null-a.mp4", domain.MediaTypeVideo, domain.MediaStatusFailed, 4, nil)
	query := domain.MediaListQuery{UserID: "user_local", Sort: domain.MediaSortDuration, Order: domain.SortDescending, Limit: 2}
	first, err := repository.List(context.Background(), query)
	if err != nil {
		t.Fatal(err)
	}
	if len(first) != 2 || first[0].ID != "media_long" || first[1].ID != "media_short" {
		t.Fatalf("first page = %#v", first)
	}
	query.After = &domain.MediaPageKey{IntValue: short, ID: "media_short"}
	second, err := repository.List(context.Background(), query)
	if err != nil {
		t.Fatal(err)
	}
	if len(second) != 2 || second[0].ID != "media_null_b" || second[1].ID != "media_null_a" {
		t.Fatalf("second page = %#v", second)
	}
	query.After = &domain.MediaPageKey{Null: true, ID: "media_null_b"}
	third, err := repository.List(context.Background(), query)
	if err != nil {
		t.Fatal(err)
	}
	if len(third) != 1 || third[0].ID != "media_null_a" {
		t.Fatalf("third page = %#v", third)
	}
}

func TestMediaRepositoryDurationSortKeepsNullLast(t *testing.T) {
	repository, sources := newMediaRepositoryTest(t)
	now := time.UnixMilli(1000).UTC()
	source := domain.Source{ID: "source", Name: "源", Type: domain.SourceTypeLocal, RootPath: "/media", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now}
	if err := sources.Create(context.Background(), source); err != nil {
		t.Fatal(err)
	}
	short, long := int64(10), int64(20)
	insertMedia(t, repository, "media_short", source.ID, "short.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 1, &short)
	insertMedia(t, repository, "media_long", source.ID, "long.mp4", domain.MediaTypeVideo, domain.MediaStatusReady, 2, &long)
	insertMedia(t, repository, "media_unknown", source.ID, "unknown.mp4", domain.MediaTypeVideo, domain.MediaStatusFailed, 3, nil)
	query := domain.MediaListQuery{UserID: "user_local", Sort: domain.MediaSortDuration, Order: domain.SortAscending, Limit: 10}
	items, err := repository.List(context.Background(), query)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 3 || items[0].ID != "media_short" || items[1].ID != "media_long" || items[2].ID != "media_unknown" {
		t.Fatalf("unexpected duration order: %#v", items)
	}
	query.After = &domain.MediaPageKey{IntValue: long, ID: "media_long"}
	items, err = repository.List(context.Background(), query)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].ID != "media_unknown" {
		t.Fatalf("unexpected page after duration: %#v", items)
	}
}
