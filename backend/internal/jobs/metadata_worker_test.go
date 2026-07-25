// Metadata worker tests verify safe work-level sidecar selection independently of filesystem access.
package jobs

import (
	"reflect"
	"testing"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

func TestSelectWorkSidecarsUsesOnlyStandardMovieNFOsInPrecedenceOrder(t *testing.T) {
	got := selectWorkSidecars(
		domain.CatalogKindMovie,
		[]string{"电影/feature.mkv"},
		[]string{
			"电影/actors/person.nfo",
			"电影/MOVIE.NFO",
			"电影/feature.nfo",
			"其他/movie.nfo",
		},
	)
	want := []string{"电影/MOVIE.NFO", "电影/feature.nfo"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("sidecars=%#v want=%#v", got, want)
	}
}

func TestSelectWorkSidecarsUsesSeriesRootTVShowNFOOnce(t *testing.T) {
	got := selectWorkSidecars(
		domain.CatalogKindSeries,
		[]string{
			"三体/Season 01/三体.S01E01.mkv",
			"三体/Season 01/三体.S01E02.mkv",
		},
		[]string{
			"三体/tvshow.nfo",
			"三体/Season 01/episode.nfo",
			"别的剧/tvshow.nfo",
		},
	)
	want := []string{"三体/tvshow.nfo"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("sidecars=%#v want=%#v", got, want)
	}
}
