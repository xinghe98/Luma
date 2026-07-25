package catalog

import (
	"fmt"
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

func TestMatchRealWorldEpisodeOnlyNames(t *testing.T) {
	tests := []struct {
		name     string
		show     string
		count    int
		filename func(int) string
	}{
		{
			name: "非自然死亡", show: "非自然死亡", count: 10,
			filename: func(episode int) string {
				return fmt.Sprintf("非自然死亡.第%d集.Unnatural.2018.E%02d.BD-1080p.X264.AAC-99Mp4.mp4", episode, episode)
			},
		},
		{
			name: "画江湖之不良人", show: "画江湖之不良人", count: 12,
			filename: func(episode int) string {
				return fmt.Sprintf("画江湖之不良人网剧版%02d.mp4", episode)
			},
		},
		{
			name: "三体", show: "三体", count: 30,
			filename: func(episode int) string {
				return fmt.Sprintf("Three.Body.2023.EP%02d.HD1080P.X264.AAC.Mandarin.CHS.BDYS.mp4", episode)
			},
		},
		{
			name: "小巷人家", show: "小巷人家/4K", count: 40,
			filename: func(episode int) string {
				return fmt.Sprintf("%02d 4K.mp4", episode)
			},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			for episode := 1; episode <= test.count; episode++ {
				filename := test.filename(episode)
				match := Match(domain.CatalogCandidate{
					MediaID: "m", SourceID: "s", LibraryKind: domain.LibraryKindTV,
					RelativePath: test.show + "/" + filename, Filename: filename,
				})
				if match.Status != domain.CatalogMatchMatched ||
					match.SeasonNumber == nil || *match.SeasonNumber != 1 ||
					match.EpisodeNumber == nil || *match.EpisodeNumber != episode {
					t.Fatalf("episode %d match = %#v", episode, match)
				}
			}
		})
	}
}

func TestMatchEpisodeSeasonDirectoriesAndTitle(t *testing.T) {
	tests := []struct {
		name         string
		relativePath string
		filename     string
		season       int
		episode      int
		title        string
	}{
		{
			name: "english season", relativePath: "剧名/Season 02/EP03.mkv",
			filename: "EP03.mkv", season: 2, episode: 3, title: "第 3 集",
		},
		{
			name: "short season", relativePath: "剧名/S03/第4集.mkv",
			filename: "第4集.mkv", season: 3, episode: 4, title: "第 4 集",
		},
		{
			name: "chinese season", relativePath: "剧名/第4季/05.mkv",
			filename: "05.mkv", season: 4, episode: 5, title: "第 5 集",
		},
		{
			name: "specials", relativePath: "剧名/Specials/E02.mkv",
			filename: "E02.mkv", season: 0, episode: 2, title: "第 2 集",
		},
		{
			name: "episode title", relativePath: "剧名/Season 01/剧名.S01E03.真正的标题.1080p.mkv",
			filename: "剧名.S01E03.真正的标题.1080p.mkv", season: 1, episode: 3, title: "真正的标题",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			match := Match(domain.CatalogCandidate{
				MediaID: "m", SourceID: "s", LibraryKind: domain.LibraryKindTV,
				RelativePath: test.relativePath, Filename: test.filename,
			})
			if match.Status != domain.CatalogMatchMatched ||
				match.SeasonNumber == nil || *match.SeasonNumber != test.season ||
				match.EpisodeNumber == nil || *match.EpisodeNumber != test.episode ||
				match.EpisodeTitle != test.title {
				t.Fatalf("match = %#v", match)
			}
		})
	}
}

func TestMatchAmbiguousTVNamesNeedReview(t *testing.T) {
	tests := []struct {
		name         string
		relativePath string
		filename     string
	}{
		{name: "year", relativePath: "剧名/2023.mkv", filename: "2023.mkv"},
		{name: "resolution", relativePath: "剧名/1080p.mkv", filename: "1080p.mkv"},
		{name: "quality", relativePath: "剧名/4K.mkv", filename: "4K.mkv"},
		{name: "unnumbered", relativePath: "剧名/片段.mkv", filename: "片段.mkv"},
		{name: "conflicting episodes", relativePath: "剧名/剧名.第2集.E03.mkv", filename: "剧名.第2集.E03.mkv"},
		{name: "conflicting seasons", relativePath: "剧名/Season 02/剧名.S01E03.mkv", filename: "剧名.S01E03.mkv"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			match := Match(domain.CatalogCandidate{
				LibraryKind:  domain.LibraryKindTV,
				RelativePath: test.relativePath,
				Filename:     test.filename,
			})
			if match.Status != domain.CatalogMatchNeedsReview {
				t.Fatalf("match = %#v", match)
			}
		})
	}
}

func TestMatchUnnumberedTVNeedsReview(t *testing.T) {
	match := Match(domain.CatalogCandidate{LibraryKind: domain.LibraryKindTV, RelativePath: "剧名/片段.mkv", Filename: "片段.mkv"})
	if match.Status != domain.CatalogMatchNeedsReview {
		t.Fatalf("status = %s", match.Status)
	}
}
