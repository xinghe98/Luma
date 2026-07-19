package api

import (
	"os"
	"path/filepath"
	"testing"

	"gopkg.in/yaml.v3"
)

// TestOpenAPIIsValidYAML 防止接口契约因编辑错误变成不可解析的 YAML。
func TestOpenAPIIsValidYAML(t *testing.T) {
	content, err := os.ReadFile(filepath.Join("..", "..", "api", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := yaml.Unmarshal(content, &document); err != nil {
		t.Fatal(err)
	}
	if document["openapi"] != "3.1.0" {
		t.Fatalf("openapi version = %#v", document["openapi"])
	}
	paths, ok := document["paths"].(map[string]any)
	if !ok {
		t.Fatal("OpenAPI paths 缺失")
	}
	original, ok := paths["/api/v1/media/{id}/original"].(map[string]any)
	if !ok || original["get"] == nil || original["head"] == nil {
		t.Fatalf("原图 GET/HEAD 契约缺失: %#v", original)
	}
	for _, path := range []string{
		"/api/v1/media/continue-watching", "/api/v1/media/{id}/user-data",
		"/api/v1/media/{id}/progress", "/api/v1/tags", "/api/v1/tags/{id}",
	} {
		if paths[path] == nil {
			t.Fatalf("阶段 6 OpenAPI path 缺失: %s", path)
		}
	}
	components, ok := document["components"].(map[string]any)
	if !ok {
		t.Fatal("OpenAPI components 缺失")
	}
	schemas, ok := components["schemas"].(map[string]any)
	if !ok {
		t.Fatal("OpenAPI schemas 缺失")
	}
	mediaSummary, ok := schemas["MediaSummary"].(map[string]any)
	if !ok {
		t.Fatal("MediaSummary schema 缺失")
	}
	properties, ok := mediaSummary["properties"].(map[string]any)
	if !ok || properties["original_url"] == nil {
		t.Fatal("MediaSummary.original_url 契约缺失")
	}
	for _, property := range []string{"completed", "last_played_at", "user_data_revision"} {
		if properties[property] == nil {
			t.Fatalf("MediaSummary.%s 契约缺失", property)
		}
	}
	for _, schema := range []string{"Tag", "MediaUserData", "UpdateMediaUserData", "UpdateProgress"} {
		if schemas[schema] == nil {
			t.Fatalf("阶段 6 schema 缺失: %s", schema)
		}
	}
}
