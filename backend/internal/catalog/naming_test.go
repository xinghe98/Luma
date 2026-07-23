package catalog

import (
	"testing"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestMatchMovieDirectory(t *testing.T) {
	match := Match(domain.CatalogCandidate{MediaID: "m", SourceID: "s", LibraryKind: domain.LibraryKindMovies,
		RelativePath: "流浪地球 2 (2023)/The.Wandering.Earth.II.2160p.mkv", Filename: "The.Wandering.Earth.II.2160p.mkv", MediaUpdatedAt: time.Now()})
	if match.Title != "流浪地球 2" || match.Year == nil || *match.Year != 2023 || match.Kind != domain.CatalogKindMovie {
		t.Fatalf("unexpected match: %#v", match)
	}
}

func TestMatchEpisode(t *testing.T) {
	match := Match(domain.CatalogCandidate{MediaID: "m", SourceID: "s", LibraryKind: domain.LibraryKindTV,
		RelativePath: "漫长的季节/Season 01/漫长的季节.S01E03.mp4", Filename: "漫长的季节.S01E03.mp4", MediaUpdatedAt: time.Now()})
	if match.Title != "漫长的季节" || match.SeasonNumber == nil || *match.SeasonNumber != 1 || match.EpisodeNumber == nil || *match.EpisodeNumber != 3 {
		t.Fatalf("unexpected match: %#v", match)
	}
}

func TestMatchUnnumberedTVNeedsReview(t *testing.T) {
	match := Match(domain.CatalogCandidate{LibraryKind: domain.LibraryKindTV, RelativePath: "剧名/片段.mkv", Filename: "片段.mkv"})
	if match.Status != domain.CatalogMatchNeedsReview {
		t.Fatalf("status = %s", match.Status)
	}
}
