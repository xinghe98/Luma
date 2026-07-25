package sqlite

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/catalog"
	"github.com/xinghe98/Luma/backend/internal/config"
	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestCatalogRepositoryGroupsMoviesAndEpisodes(t *testing.T) {
	ctx := context.Background()
	db, err := Open(ctx, config.DatabaseConfig{Path: filepath.Join(t.TempDir(), "catalog.db"), BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	sources, _ := NewSourceRepository(db)
	repository, _ := NewCatalogRepository(db)
	now := time.UnixMilli(10_000).UTC()
	for _, source := range []domain.Source{
		{ID: "movies", Name: "电影", Type: domain.SourceTypeLocal, LibraryKind: domain.LibraryKindMovies, RootPath: "/movies", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now},
		{ID: "tv", Name: "剧集", Type: domain.SourceTypeLocal, LibraryKind: domain.LibraryKindTV, RootPath: "/tv", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now},
	} {
		if err := sources.Create(ctx, source); err != nil {
			t.Fatal(err)
		}
	}
	insertCatalogMedia := func(id, sourceID, relativePath, filename string) {
		_, err := db.Exec(`INSERT INTO media_items(id,source_id,relative_path,filename,media_type,file_size,file_modified_at_ms,status,discovered_at_ms,created_at_ms,updated_at_ms)
			VALUES(?,?,?,?, 'video',100,1,'ready',?,?,?)`, id, sourceID, relativePath, filename, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
		if err != nil {
			t.Fatal(err)
		}
	}
	insertCatalogMedia("movie", "movies", "流浪地球 2 (2023)/movie.mkv", "movie.mkv")
	_, err = db.Exec(`INSERT INTO media_items(id,source_id,relative_path,filename,media_type,file_size,file_modified_at_ms,status,discovered_at_ms,created_at_ms,updated_at_ms)
		VALUES('movie_poster','movies','流浪地球 2 (2023)/poster.jpg','poster.jpg','image',100,1,'ready',?,?,?)`, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`INSERT INTO media_assets(id,media_id,asset_type,variant,storage_key,status,generator_version,created_at_ms,updated_at_ms)
		VALUES('poster_asset','movie_poster','thumbnail','default','thumbnails/movie_poster/cover.jpg','ready',1,?,?)`, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	insertCatalogMedia("episode1", "tv", "漫长的季节/Season 01/漫长的季节.S01E01.mkv", "漫长的季节.S01E01.mkv")
	insertCatalogMedia("episode2", "tv", "漫长的季节/Season 01/漫长的季节.S01E02.mkv", "漫长的季节.S01E02.mkv")
	for id, dimensions := range map[string][2]int{
		"movie":    {3840, 2160},
		"episode1": {1920, 1080},
		"episode2": {1280, 720},
	} {
		if _, err := db.Exec(`UPDATE media_items SET width = ?, height = ? WHERE id = ?`, dimensions[0], dimensions[1], id); err != nil {
			t.Fatal(err)
		}
	}

	candidates, err := repository.ListCandidates(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(candidates) != 3 {
		t.Fatalf("candidate count = %d", len(candidates))
	}
	for _, candidate := range candidates {
		if err := repository.SaveMatch(ctx, catalog.Match(candidate), now); err != nil {
			t.Fatal(err)
		}
	}
	items, err := repository.List(ctx, domain.CatalogListRequest{Limit: 10}, "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 {
		t.Fatalf("catalog count = %d, items=%#v", len(items), items)
	}
	var movie, series domain.CatalogItem
	for _, item := range items {
		if item.Kind == domain.CatalogKindMovie {
			movie = item
		}
		if item.Kind == domain.CatalogKindSeries {
			series = item
		}
	}
	if series.Title != "漫长的季节" || series.EpisodeCount != 2 || len(series.Episodes) != 0 {
		t.Fatalf("unexpected series: %#v", series)
	}
	detail, err := repository.Get(ctx, series.ID, "user_local")
	if err != nil || len(detail.Episodes) != 2 {
		t.Fatalf("catalog detail=%#v error=%v", detail, err)
	}
	if movie.Resolution != "3840×2160" {
		t.Fatalf("movie resolution = %q", movie.Resolution)
	}
	if detail.Episodes[0].Resolution != "1920×1080" || detail.Episodes[1].Resolution != "1280×720" {
		t.Fatalf("episode resolutions = %#v", detail.Episodes)
	}
	if movie.PosterMediaID != "movie_poster" {
		t.Fatalf("movie poster = %q", movie.PosterMediaID)
	}
}

func TestCatalogRepositoryKeepsManualMatchLocked(t *testing.T) {
	ctx := context.Background()
	db, err := Open(ctx, config.DatabaseConfig{Path: filepath.Join(t.TempDir(), "manual.db"), BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	sources, _ := NewSourceRepository(db)
	repository, _ := NewCatalogRepository(db)
	now := time.UnixMilli(10_000).UTC()
	if err := sources.Create(ctx, domain.Source{ID: "tv", Name: "剧集", Type: domain.SourceTypeLocal, LibraryKind: domain.LibraryKindTV, RootPath: "/tv", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now}); err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`INSERT INTO media_items(id,source_id,relative_path,filename,media_type,file_size,file_modified_at_ms,status,discovered_at_ms,created_at_ms,updated_at_ms)
		VALUES('clip','tv','剧名/片段.mkv','片段.mkv','video',100,1,'ready',?,?,?)`, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	candidate, err := repository.GetCandidate(ctx, "clip")
	if err != nil {
		t.Fatal(err)
	}
	season, episode := 1, 4
	manual := domain.CatalogMatch{MediaID: "clip", SourceID: "tv", Kind: domain.CatalogKindSeries, Title: "手动剧名", SortTitle: catalog.NormalizeTitle("手动剧名"), SeasonNumber: &season, EpisodeNumber: &episode, EpisodeTitle: "第 4 集", Status: domain.CatalogMatchMatched, Confidence: 100, Locked: true, MediaUpdatedAt: candidate.MediaUpdatedAt}
	if err := repository.SaveMatch(ctx, manual, now); err != nil {
		t.Fatal(err)
	}
	candidates, err := repository.ListCandidates(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(candidates) != 0 {
		t.Fatalf("locked mapping returned as dirty: %#v", candidates)
	}
}

func TestCatalogRepositoryRuleUpgradeClearsNeedsReview(t *testing.T) {
	ctx := context.Background()
	db, err := Open(ctx, config.DatabaseConfig{Path: filepath.Join(t.TempDir(), "rematch.db"), BusyTimeoutMS: 1000})
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	sources, _ := NewSourceRepository(db)
	repository, _ := NewCatalogRepository(db)
	now := time.UnixMilli(10_000).UTC()
	if err := sources.Create(ctx, domain.Source{
		ID: "tv", Name: "剧集", Type: domain.SourceTypeLocal, LibraryKind: domain.LibraryKindTV,
		RootPath: "/tv", Enabled: true, Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now,
	}); err != nil {
		t.Fatal(err)
	}
	shows := []struct {
		id           string
		title        string
		relativePath string
		filename     string
	}{
		{
			id: "unnatural", title: "非自然死亡",
			relativePath: "非自然死亡/非自然死亡.第10集.Unnatural.2018.E10.BD-1080p.mkv",
			filename:     "非自然死亡.第10集.Unnatural.2018.E10.BD-1080p.mkv",
		},
		{
			id: "bad_people", title: "画江湖之不良人",
			relativePath: "画江湖之不良人/画江湖之不良人网剧版01.mp4/画江湖之不良人网剧版01.mp4",
			filename:     "画江湖之不良人网剧版01.mp4",
		},
		{
			id: "three_body", title: "三体",
			relativePath: "三体/Three.Body.2023.EP01.HD1080P.mkv",
			filename:     "Three.Body.2023.EP01.HD1080P.mkv",
		},
		{
			id: "alley", title: "小巷人家",
			relativePath: "小巷人家/4K/01 4K.mp4",
			filename:     "01 4K.mp4",
		},
	}
	for _, show := range shows {
		_, err := db.Exec(`INSERT INTO media_items(id,source_id,relative_path,filename,media_type,file_size,file_modified_at_ms,status,discovered_at_ms,created_at_ms,updated_at_ms)
			VALUES(?,?,?,?, 'video',100,1,'ready',?,?,?)`,
			show.id, "tv", show.relativePath, show.filename, now.UnixMilli(), now.UnixMilli(), now.UnixMilli())
		if err != nil {
			t.Fatal(err)
		}
		oldMatch := domain.CatalogMatch{
			MediaID: show.id, SourceID: "tv", Kind: domain.CatalogKindSeries,
			Title: show.title, SortTitle: catalog.NormalizeTitle(show.title),
			Status: domain.CatalogMatchNeedsReview, Confidence: 35, MediaUpdatedAt: now,
		}
		if err := repository.SaveMatch(ctx, oldMatch, now); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(`UPDATE catalog_media_links SET rule_version = 1`); err != nil {
		t.Fatal(err)
	}

	candidates, err := repository.ListCandidates(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(candidates) != len(shows) {
		t.Fatalf("candidate count = %d", len(candidates))
	}
	for _, candidate := range candidates {
		if err := repository.SaveMatch(ctx, catalog.Match(candidate), now.Add(time.Second)); err != nil {
			t.Fatal(err)
		}
	}

	var matched, needsReview, ruleVersion int
	if err := db.QueryRow(`SELECT
		SUM(CASE WHEN match_status = 'matched' THEN 1 ELSE 0 END),
		SUM(CASE WHEN match_status = 'needs_review' THEN 1 ELSE 0 END),
		MIN(rule_version)
		FROM catalog_media_links`).Scan(&matched, &needsReview, &ruleVersion); err != nil {
		t.Fatal(err)
	}
	if matched != len(shows) || needsReview != 0 || ruleVersion != catalog.RuleVersion {
		t.Fatalf("links matched=%d needs_review=%d rule=%d", matched, needsReview, ruleVersion)
	}
	var matchedItems int
	if err := db.QueryRow(`SELECT COUNT(*) FROM catalog_items WHERE match_status = 'matched'`).Scan(&matchedItems); err != nil {
		t.Fatal(err)
	}
	if matchedItems != len(shows) {
		t.Fatalf("matched catalog item count = %d", matchedItems)
	}
	items, err := repository.List(ctx, domain.CatalogListRequest{Kind: domain.CatalogKindSeries, Limit: 10}, "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != len(shows) {
		t.Fatalf("catalog items = %#v", items)
	}
	found := make(map[string]domain.CatalogItem, len(items))
	for _, item := range items {
		found[item.Title] = item
	}
	for _, show := range shows {
		if item, ok := found[show.title]; !ok || item.EpisodeCount != 1 {
			t.Fatalf("catalog item %q = %#v, found=%v", show.title, item, ok)
		}
	}
	issues, err := repository.ListIssues(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(issues) != 0 {
		t.Fatalf("issues = %#v", issues)
	}
}
