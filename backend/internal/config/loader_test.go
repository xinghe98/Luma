package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestLoadAppliesDefaultsAndResolvesPaths 验证默认值和相对路径解析行为。
func TestLoadAppliesDefaultsAndResolvesPaths(t *testing.T) {
	base := t.TempDir()
	media := filepath.Join(base, "media")
	if err := os.Mkdir(media, 0o755); err != nil {
		t.Fatal(err)
	}
	content := `
security:
  api_token_file: data/token
  allowed_roots: [media]
database:
  path: data/media.db
storage:
  thumbnail_dir: data/thumbnails
  cache_dir: data/cache
`
	path := filepath.Join(base, "config.yaml")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Server.Port != 8080 || cfg.Media.ThumbnailWidth != 640 {
		t.Fatal("defaults were not applied")
	}
	if !filepath.IsAbs(cfg.Database.Path) || cfg.Security.AllowedRoots[0] != media {
		t.Fatal("paths were not resolved relative to the config file")
	}
}

// TestLoadRejectsUnknownFields 验证配置加载器拒绝未知字段。
func TestLoadRejectsUnknownFields(t *testing.T) {
	base := t.TempDir()
	path := filepath.Join(base, "config.yaml")
	if err := os.WriteFile(path, []byte("unknown: true\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := Load(path)
	if err == nil || !strings.Contains(err.Error(), "field unknown not found") {
		t.Fatalf("expected unknown field error, got %v", err)
	}
}
