// 本文件覆盖刮削队列、人工身份、丰富资料与刷新状态的持久化行为。
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

func TestCatalogMetadataQueueIdentityAndRichResult(t *testing.T) {
	ctx := context.Background()
	db, err := Open(ctx, config.DatabaseConfig{
		Path: filepath.Join(t.TempDir(), "metadata.db"), BusyTimeoutMS: 1000,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	sources, err := NewSourceRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	repository, err := NewCatalogRepository(db)
	if err != nil {
		t.Fatal(err)
	}
	now := time.UnixMilli(10_000).UTC()
	if err := sources.Create(ctx, domain.Source{
		ID: "movies", Name: "电影", Type: domain.SourceTypeLocal,
		LibraryKind: domain.LibraryKindMovies, RootPath: "/movies", Enabled: true,
		Status: domain.SourceStatusOnline, CreatedAt: now, UpdatedAt: now,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO media_items(
		id,source_id,relative_path,filename,media_type,file_size,file_modified_at_ms,status,
		discovered_at_ms,created_at_ms,updated_at_ms
	) VALUES('movie','movies','三体 (2023)/movie.mkv','movie.mkv','video',100,1,'ready',?,?,?)`,
		now.UnixMilli(), now.UnixMilli(), now.UnixMilli()); err != nil {
		t.Fatal(err)
	}
	candidate, err := repository.GetCandidate(ctx, "movie")
	if err != nil {
		t.Fatal(err)
	}
	match := catalog.Match(candidate)
	if err := repository.SaveMatch(ctx, match, now); err != nil {
		t.Fatal(err)
	}
	items, err := repository.List(ctx, domain.CatalogListRequest{Limit: 10}, "user_local")
	if err != nil || len(items) != 1 {
		t.Fatalf("items=%#v error=%v", items, err)
	}
	itemID := items[0].ID

	if count, err := repository.EnqueuePendingMetadata(ctx, now, now.Add(-time.Hour)); err != nil || count != 1 {
		t.Fatalf("enqueue count=%d error=%v", count, err)
	}
	input, err := repository.ClaimMetadata(ctx, "worker_one", now)
	if err != nil || input.ItemID != itemID || input.Title != "三体" {
		t.Fatalf("input=%#v error=%v", input, err)
	}
	year := 2023
	if err := repository.SaveMetadataCandidates(ctx, itemID, []domain.CatalogMetadataCandidate{{
		ID: "candidate_tmdb_1", ItemID: itemID, Provider: "tmdb", ProviderItemID: "1",
		Title: "三体", OriginalTitle: "三体", Year: &year, Score: 88,
		Reasons: []string{"标题完全匹配"},
	}}, now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	candidates, err := repository.ListMetadataCandidates(ctx, itemID)
	if err != nil || len(candidates) != 1 || candidates[0].Score != 88 {
		t.Fatalf("candidates=%#v error=%v", candidates, err)
	}
	if err := repository.SelectMetadataIdentity(ctx, itemID, "tmdb", "1", 1, now.Add(2*time.Second)); err != nil {
		t.Fatal(err)
	}
	input, err = repository.ClaimMetadata(ctx, "worker_two", now.Add(2*time.Second))
	if err != nil || !input.IdentityLocked || input.ProviderItemID != "1" {
		t.Fatalf("locked input=%#v error=%v", input, err)
	}
	rating := 8.7
	runtime := int64((125 * time.Minute) / time.Millisecond)
	if err := repository.CompleteMetadata(ctx, domain.CatalogMetadataResult{
		ItemID: itemID, Provider: "tmdb", ProviderItemID: "1", Title: "三体",
		OriginalTitle: "Three-Body", AlternativeTitles: []string{"Three Body"},
		Overview: "丰富简介", ReleaseDate: "2023-01-15", RuntimeMS: &runtime,
		CommunityRating: &rating, VoteCount: 1200,
		GenresJSON: `[{"id":"18","name":"剧情"}]`, CountriesJSON: `[]`,
		StudiosJSON: `[]`, CreditsJSON: `[
			{"provider_person_id":"person_1","name":"演员","character":"角色","order":0,"profile":{"provider":"tmdb","key":"/profile.jpg"}},
			{"provider_person_id":"person_1","name":"演员","department":"Production","job":"Producer","order":1,"profile":{"provider":"tmdb","key":"/profile.jpg"}}
		]`, ExternalIDsJSON: `{"imdb":"tt20242042"}`,
		PosterRef: "/poster.jpg", BackdropRef: "/backdrop.jpg",
	}, now.Add(3*time.Second)); err != nil {
		t.Fatal(err)
	}
	detail, err := repository.Get(ctx, itemID, "user_local")
	if err != nil {
		t.Fatal(err)
	}
	if detail.MetadataStatus != "ready" || detail.Provider != "tmdb" ||
		detail.Overview != "丰富简介" || detail.OriginalTitle != "Three-Body" ||
		!detail.IdentityLocked || len(detail.Genres) != 1 ||
		detail.PosterArtworkID == "" || detail.BackdropArtworkID == "" ||
		len(detail.Credits) != 2 || detail.Credits[0].ProfileArtworkID == "" ||
		detail.Credits[0].ProfileArtworkID != detail.Credits[1].ProfileArtworkID {
		t.Fatalf("detail=%#v", detail)
	}
	profile, err := repository.GetCatalogArtwork(ctx, detail.Credits[0].ProfileArtworkID, "user_local")
	if err != nil || profile.OpaqueKey != "/profile.jpg" {
		t.Fatalf("profile=%#v error=%v", profile, err)
	}

	// An identity lock fixes the selected record, not its metadata snapshot.
	if count, err := repository.EnqueuePendingMetadata(
		ctx, now.Add(40*24*time.Hour), now.Add(10*24*time.Hour),
	); err != nil || count != 1 {
		t.Fatalf("locked refresh count=%d error=%v", count, err)
	}
	if _, err := repository.ClaimMetadata(ctx, "worker_three", now.Add(40*24*time.Hour)); err != nil {
		t.Fatalf("claim locked refresh: %v", err)
	}
}
