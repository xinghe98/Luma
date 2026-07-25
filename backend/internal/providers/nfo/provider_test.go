// NFO provider tests cover partial fields and external identity parsing.
package nfo

import (
	"context"
	"strings"
	"testing"

	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

func TestParseSidecar(t *testing.T) {
	input := `<movie><title>重庆森林</title><originaltitle>重慶森林</originaltitle><year>1994</year>` +
		`<runtime>102</runtime><genre>剧情</genre><uniqueid type="tmdb">11104</uniqueid></movie>`
	patch, err := New().ParseSidecar(context.Background(), scraper.SidecarRequest{
		Kind: scraper.MediaKindMovie, Body: strings.NewReader(input),
	})
	if err != nil {
		t.Fatal(err)
	}
	if patch.Title == nil || *patch.Title != "重庆森林" || patch.Year == nil || *patch.Year != 1994 ||
		patch.ExternalIDs["tmdb"] != "11104" || patch.Genres == nil || len(*patch.Genres) != 1 {
		t.Fatalf("patch = %#v", patch)
	}
}
