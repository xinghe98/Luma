package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
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
  admin_username: admin
  admin_password_file: data/admin_password
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

// TestAutoScanDefaultsAndValidation 验证自动扫描默认开启且非法 mode 被拒绝。
func TestAutoScanDefaultsAndValidation(t *testing.T) {
	base := t.TempDir()
	media := filepath.Join(base, "media")
	if err := os.Mkdir(media, 0o755); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(base, "config.yaml")
	content := `
security:
  admin_username: admin
  admin_password_file: data/admin_password
  allowed_roots: [media]
database:
  path: data/media.db
storage:
  thumbnail_dir: data/thumbnails
  cache_dir: data/cache
`
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.Media.AutoScan.Enabled {
		t.Fatal("auto_scan should default to enabled")
	}
	if cfg.Media.AutoScan.Mode != AutoScanModeHybrid || cfg.Media.AutoScan.Interval != 30*time.Minute {
		t.Fatalf("auto_scan defaults = %#v", cfg.Media.AutoScan)
	}
	bad := cfg
	bad.Media.AutoScan.Mode = "daily"
	if err := Validate(bad); err == nil || !strings.Contains(err.Error(), "media.auto_scan.mode") {
		t.Fatalf("expected mode validation error, got %v", err)
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
