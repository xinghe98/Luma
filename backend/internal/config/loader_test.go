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
	if cfg.Server.Port != 8080 || cfg.Server.ReadTimeout != 30*time.Second || cfg.Media.ThumbnailWidth != 640 {
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

// TestValidateRequiresTLSOrExplicitRemotePlaintext 验证非回环明文监听必须显式确认。
func TestValidateRequiresTLSOrExplicitRemotePlaintext(t *testing.T) {
	cfg := validTestConfig(t)
	cfg.Server.Host = "0.0.0.0"
	if err := Validate(cfg); err == nil || !strings.Contains(err.Error(), "allow_insecure_remote") {
		t.Fatalf("expected remote plaintext validation error, got %v", err)
	}
	cfg.Server.AllowInsecureRemote = true
	if err := Validate(cfg); err != nil {
		t.Fatalf("explicit remote plaintext rejected: %v", err)
	}
	cfg.Server.AllowInsecureRemote = false
	cfg.Server.TLSCertFile = filepath.Join(t.TempDir(), "server.crt")
	cfg.Server.TLSKeyFile = filepath.Join(t.TempDir(), "server.key")
	if err := Validate(cfg); err != nil {
		t.Fatalf("TLS remote listener rejected: %v", err)
	}
}

// TestValidateComparesFinalDataAndMediaPaths 验证数据路径通过链接落入媒体目录时仍会被拒绝。
func TestValidateComparesFinalDataAndMediaPaths(t *testing.T) {
	cfg := validTestConfig(t)
	link := filepath.Join(t.TempDir(), "database-link")
	if err := os.Symlink(cfg.Security.AllowedRoots[0], link); err != nil {
		t.Skipf("当前环境不支持符号链接: %v", err)
	}
	cfg.Database.Path = filepath.Join(link, "media.db")
	err := Validate(cfg)
	if err == nil || (!strings.Contains(err.Error(), "符号链接") && !strings.Contains(err.Error(), "media root")) {
		t.Fatalf("expected linked data path rejection, got %v", err)
	}
}

// TestPrepareDataDirectoriesRechecksReboundPath 验证加载后出现的数据目录链接会在创建前被拒绝。
func TestPrepareDataDirectoriesRechecksReboundPath(t *testing.T) {
	cfg := validTestConfig(t)
	data := filepath.Dir(cfg.Database.Path)
	if err := os.Symlink(cfg.Security.AllowedRoots[0], data); err != nil {
		t.Skipf("当前环境不支持符号链接: %v", err)
	}
	if err := PrepareDataDirectories(cfg); err == nil || !strings.Contains(err.Error(), "符号链接") {
		t.Fatalf("expected rebound data path rejection, got %v", err)
	}
}

// validTestConfig 返回可独立交给 Validate 的最小有效配置。
func validTestConfig(t *testing.T) Config {
	t.Helper()
	base := t.TempDir()
	media := filepath.Join(base, "media")
	if err := os.Mkdir(media, 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := defaults()
	cfg.Security.AllowedRoots = []string{media}
	cfg.Security.AdminPasswordFile = filepath.Join(base, "data", "admin_password")
	cfg.Database.Path = filepath.Join(base, "data", "media.db")
	cfg.Storage.ThumbnailDir = filepath.Join(base, "data", "thumbnails")
	cfg.Storage.CacheDir = filepath.Join(base, "data", "cache")
	return cfg
}
