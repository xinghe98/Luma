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
		"/api/v1/media/count",
	} {
		if paths[path] == nil {
			t.Fatalf("阶段 6 OpenAPI path 缺失: %s", path)
		}
	}
	for _, path := range []string{"/api/v1/catalog", "/api/v1/catalog/issues", "/api/v1/catalog/media/{id}", "/api/v1/catalog/{id}"} {
		if paths[path] == nil {
			t.Fatalf("作品库 OpenAPI path 缺失: %s", path)
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
	for _, property := range []string{"completed", "last_played_at", "user_data_revision", "created_at"} {
		if properties[property] == nil {
			t.Fatalf("MediaSummary.%s 契约缺失", property)
		}
	}
	required, ok := mediaSummary["required"].([]any)
	if !ok || !containsYAMLString(required, "created_at") {
		t.Fatal("MediaSummary.created_at 未标记为 required")
	}
	mediaDetail, ok := schemas["MediaDetail"].(map[string]any)
	if !ok {
		t.Fatal("MediaDetail schema 缺失")
	}
	allOf, ok := mediaDetail["allOf"].([]any)
	if !ok || len(allOf) != 2 {
		t.Fatal("MediaDetail allOf 契约缺失")
	}
	detailExtension, ok := allOf[1].(map[string]any)
	if !ok {
		t.Fatal("MediaDetail 扩展契约缺失")
	}
	detailProperties, _ := detailExtension["properties"].(map[string]any)
	if detailProperties["created_at"] != nil {
		t.Fatal("MediaDetail 不应重复定义 created_at")
	}
	mediaPath, ok := paths["/api/v1/media"].(map[string]any)
	get, getOK := mediaPath["get"].(map[string]any)
	parameters, parametersOK := get["parameters"].([]any)
	if !ok || !getOK || !parametersOK || !hasQueryParameter(parameters, "watch_status") {
		t.Fatal("GET /api/v1/media watch_status 参数契约缺失")
	}
	for _, schema := range []string{"Tag", "MediaUserData", "UpdateMediaUserData", "UpdateProgress", "MediaCount"} {
		if schemas[schema] == nil {
			t.Fatalf("阶段 6 schema 缺失: %s", schema)
		}
	}
	for _, schema := range []string{"CatalogItem", "CatalogEpisode", "CatalogIssue", "UpdateCatalogMatch"} {
		if schemas[schema] == nil {
			t.Fatalf("作品库 schema 缺失: %s", schema)
		}
	}
}

func containsYAMLString(values []any, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}

func hasQueryParameter(parameters []any, name string) bool {
	for _, value := range parameters {
		parameter, ok := value.(map[string]any)
		if ok && parameter["in"] == "query" && parameter["name"] == name {
			return true
		}
	}
	return false
}
