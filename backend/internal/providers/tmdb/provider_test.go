// TMDb provider tests use a local HTTP server so network behavior is deterministic.
package tmdb

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/xinghe98/Luma/backend/pkg/scraper"
)

func TestSearchNormalizesMovie(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer token" {
			t.Fatalf("authorization = %q", r.Header.Get("Authorization"))
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"results":[{"id":11104,"title":"重庆森林","original_title":"重慶森林","release_date":"1994-07-14","poster_path":"/poster.jpg"}]}`))
	}))
	defer server.Close()
	provider, err := New(map[string]any{
		"access_token": "token", "api_base_url": server.URL, "image_base_url": server.URL,
	}, server.Client())
	if err != nil {
		t.Fatal(err)
	}
	page, err := provider.Search(context.Background(), scraper.SearchRequest{
		Kind: scraper.MediaKindMovie, Query: "Chungking Express",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 1 || page.Items[0].ProviderItemID != "11104" || page.Items[0].Title != "重庆森林" {
		t.Fatalf("page = %#v", page)
	}
}

func TestNewRejectsUnknownOrMissingOptions(t *testing.T) {
	if _, err := New(map[string]any{"unknown": true}, http.DefaultClient); err == nil || !strings.Contains(err.Error(), "unknown") {
		t.Fatalf("error = %v", err)
	}
	if _, err := New(map[string]any{}, http.DefaultClient); err == nil {
		t.Fatal("expected missing token error")
	}
}
