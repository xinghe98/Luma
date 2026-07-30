package api

import (
	"os"
	"path/filepath"
	"strings"
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
	servers, ok := document["servers"].([]any)
	if !ok || len(servers) < 2 {
		t.Fatal("OpenAPI 必须同时声明远程 TLS 与本机回环入口")
	}
	remote, remoteOK := servers[0].(map[string]any)
	loopback, loopbackOK := servers[1].(map[string]any)
	if !remoteOK || !strings.HasPrefix(stringValue(remote["url"]), "https://") ||
		!loopbackOK || !strings.HasPrefix(stringValue(loopback["url"]), "http://127.0.0.1") {
		t.Fatalf("OpenAPI server TLS 语义不完整: %#v", servers)
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
	for _, path := range []string{
		"/api/v1/catalog", "/api/v1/catalog/{id}", "/api/v1/catalog/{id}/user-data",
	} {
		if paths[path] == nil {
			t.Fatalf("作品库 OpenAPI path 缺失: %s", path)
		}
	}
	for _, path := range []string{"/api/v1/catalog/issues", "/api/v1/catalog/media/{id}"} {
		if paths[path] != nil {
			t.Fatalf("已删除的待整理 API 仍存在: %s", path)
		}
	}
	catalogUserData, ok := paths["/api/v1/catalog/{id}/user-data"].(map[string]any)
	if !ok || catalogUserData["patch"] == nil {
		t.Fatal("PATCH /api/v1/catalog/{id}/user-data 作品收藏契约缺失")
	}
	for _, path := range []string{
		"/api/v1/catalog/artwork/{id}", "/api/v1/admin/catalog/{id}/candidates",
		"/api/v1/admin/catalog/{id}/refresh", "/api/v1/admin/catalog/refresh",
		"/api/v1/admin/catalog/{id}/identity", "/api/v1/admin/metadata/status",
	} {
		if paths[path] == nil {
			t.Fatalf("影视刮削 OpenAPI path 缺失: %s", path)
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
	securitySchemes, _ := components["securitySchemes"].(map[string]any)
	bearer, _ := securitySchemes["bearerAuth"].(map[string]any)
	if !strings.Contains(stringValue(bearer["description"]), "TLS") {
		t.Fatal("Bearer 会话缺少 TLS 传输约束")
	}
	loginResponse, _ := schemas["LoginResponse"].(map[string]any)
	loginProperties, _ := loginResponse["properties"].(map[string]any)
	expiresAt, _ := loginProperties["expires_at"].(map[string]any)
	if !strings.Contains(stringValue(expiresAt["description"]), "截止时间") ||
		strings.Contains(stringValue(expiresAt["description"]), "固定返回 null") {
		t.Fatalf("LoginResponse.expires_at 期限语义不正确: %#v", expiresAt)
	}
	loginRequest, _ := schemas["LoginRequest"].(map[string]any)
	loginRequestProperties, _ := loginRequest["properties"].(map[string]any)
	if loginRequestProperties["device_key"] == nil {
		t.Fatal("LoginRequest.device_key 契约缺失")
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
	for _, schema := range []string{"CatalogItem", "CatalogEpisode", "CatalogVersion", "CatalogUserData", "UpdateCatalogUserData"} {
		if schemas[schema] == nil {
			t.Fatalf("作品库 schema 缺失: %s", schema)
		}
	}
	for _, schema := range []string{"CatalogIssue", "UpdateCatalogMatch"} {
		if schemas[schema] != nil {
			t.Fatalf("已删除的待整理 schema 仍存在: %s", schema)
		}
	}
	for _, schema := range []string{"MetadataCandidate", "SelectMetadataIdentity", "MetadataProviderStatus"} {
		if schemas[schema] == nil {
			t.Fatalf("影视刮削 schema 缺失: %s", schema)
		}
	}
}

// TestOpenAPIReferencesAndOperationsResolve 覆盖标准校验器会检查的本地引用、响应与 required 字段规则。
func TestOpenAPIReferencesAndOperationsResolve(t *testing.T) {
	content, err := os.ReadFile(filepath.Join("..", "..", "api", "openapi.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := yaml.Unmarshal(content, &document); err != nil {
		t.Fatal(err)
	}
	validateOpenAPIValue(t, document, document, "document")
	paths, _ := document["paths"].(map[string]any)
	operations := map[string]bool{"get": true, "post": true, "put": true, "patch": true, "delete": true, "head": true, "options": true, "trace": true}
	for pathName, rawPath := range paths {
		pathItem, _ := rawPath.(map[string]any)
		for method, rawOperation := range pathItem {
			if !operations[method] {
				continue
			}
			operation, ok := rawOperation.(map[string]any)
			if !ok || operation["responses"] == nil {
				t.Fatalf("%s %s 缺少标准 responses 对象", strings.ToUpper(method), pathName)
			}
		}
	}
}

// TestBackendWorkflowStructure 使用仓库已有 YAML 解析器检查触发器与核心 job，避免依赖外部 actionlint。
func TestBackendWorkflowStructure(t *testing.T) {
	content, err := os.ReadFile(filepath.Join("..", "..", "..", ".github", "workflows", "backend.yml"))
	if err != nil {
		t.Fatal(err)
	}
	var workflow map[string]any
	if err := yaml.Unmarshal(content, &workflow); err != nil {
		t.Fatal(err)
	}
	triggers, ok := workflow["on"].(map[string]any)
	if !ok || triggers["push"] == nil || triggers["pull_request"] == nil {
		t.Fatalf("backend workflow 触发器错误: %#v", workflow["on"])
	}
	concurrency, _ := workflow["concurrency"].(map[string]any)
	if concurrency["pull_request"] != nil {
		t.Fatal("pull_request 被错误缩进到 concurrency")
	}
	jobs, ok := workflow["jobs"].(map[string]any)
	if !ok || jobs["test"] == nil || jobs["secure-build"] == nil {
		t.Fatalf("backend workflow 核心 job 缺失: %#v", jobs)
	}
}

func validateOpenAPIValue(t *testing.T, root map[string]any, value any, location string) {
	t.Helper()
	switch typed := value.(type) {
	case map[string]any:
		if reference, ok := typed["$ref"].(string); ok && strings.HasPrefix(reference, "#/") {
			if !openAPIReferenceExists(root, reference) {
				t.Fatalf("%s 包含无法解析的引用 %s", location, reference)
			}
		}
		if required, ok := typed["required"].([]any); ok {
			if properties, hasProperties := typed["properties"].(map[string]any); hasProperties {
				for _, rawName := range required {
					name, _ := rawName.(string)
					if properties[name] == nil {
						t.Fatalf("%s 将未声明的属性 %q 标为 required", location, name)
					}
				}
			}
		}
		for key, child := range typed {
			validateOpenAPIValue(t, root, child, location+"/"+key)
		}
	case []any:
		for _, child := range typed {
			validateOpenAPIValue(t, root, child, location+"/[]")
		}
	}
}

func openAPIReferenceExists(root map[string]any, reference string) bool {
	var current any = root
	for _, part := range strings.Split(strings.TrimPrefix(reference, "#/"), "/") {
		part = strings.ReplaceAll(strings.ReplaceAll(part, "~1", "/"), "~0", "~")
		object, ok := current.(map[string]any)
		if !ok {
			return false
		}
		current, ok = object[part]
		if !ok {
			return false
		}
	}
	return true
}

func stringValue(value any) string {
	result, _ := value.(string)
	return result
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
