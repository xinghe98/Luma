package config

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// defaultExtensions 保存未显式配置时支持的媒体扩展名。
var defaultExtensions = []string{
	"mp4", "mkv", "mov", "avi", "webm", "m4v", "ts",
	"jpg", "jpeg", "png", "webp", "gif", "bmp",
}

// Load 从 YAML 文件加载、规范化并校验配置。
func Load(path string) (Config, error) {
	f, err := os.Open(path)
	if err != nil {
		return Config{}, fmt.Errorf("open config: %w", err)
	}
	defer f.Close()

	cfg := defaults()
	decoder := yaml.NewDecoder(f)
	decoder.KnownFields(true)
	if err := decoder.Decode(&cfg); err != nil {
		return Config{}, fmt.Errorf("decode config: %w", err)
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return Config{}, errors.New("decode config: multiple YAML documents are not supported")
		}
		return Config{}, fmt.Errorf("decode config: %w", err)
	}

	if err := resolvePaths(&cfg, filepath.Dir(path)); err != nil {
		return Config{}, err
	}
	if err := Validate(cfg); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

// defaults 返回可用于本地运行的默认配置值。
func defaults() Config {
	return Config{
		Server: ServerConfig{
			Host: "0.0.0.0", Port: 8080,
			ReadHeaderTimeout: 10 * time.Second,
			IdleTimeout:       60 * time.Second,
			ShutdownTimeout:   30 * time.Second,
		},
		Database: DatabaseConfig{BusyTimeoutMS: 5000, WAL: true},
		Media: MediaConfig{
			FFmpegPath: "ffmpeg", FFprobePath: "ffprobe",
			ThumbnailWidth: 640, ScanExtensions: append([]string(nil), defaultExtensions...),
		},
		Workers: WorkersConfig{Scan: 1, Probe: 2, Thumbnail: 1, LockTimeout: 10 * time.Minute},
	}
}

// resolvePaths 将配置中的相对路径转换为相对配置文件目录的绝对路径。
func resolvePaths(cfg *Config, base string) error {
	paths := []*string{
		&cfg.Security.APITokenFile,
		&cfg.Database.Path,
		&cfg.Storage.ThumbnailDir,
		&cfg.Storage.CacheDir,
	}
	for _, value := range paths {
		if *value == "" || filepath.IsAbs(*value) {
			continue
		}
		absolute, err := filepath.Abs(filepath.Join(base, *value))
		if err != nil {
			return fmt.Errorf("resolve path %q: %w", *value, err)
		}
		*value = absolute
	}
	for i := range cfg.Security.AllowedRoots {
		if filepath.IsAbs(cfg.Security.AllowedRoots[i]) {
			continue
		}
		absolute, err := filepath.Abs(filepath.Join(base, cfg.Security.AllowedRoots[i]))
		if err != nil {
			return fmt.Errorf("resolve allowed root %q: %w", cfg.Security.AllowedRoots[i], err)
		}
		cfg.Security.AllowedRoots[i] = absolute
	}
	return nil
}

// Validate 校验配置字段、目录状态和只读媒体边界。
func Validate(cfg Config) error {
	var problems []string
	if strings.TrimSpace(cfg.Server.Host) == "" {
		problems = append(problems, "server.host is required")
	}
	if cfg.Server.Port < 1 || cfg.Server.Port > 65535 {
		problems = append(problems, "server.port must be between 1 and 65535")
	}
	if cfg.Server.ReadHeaderTimeout <= 0 || cfg.Server.IdleTimeout <= 0 || cfg.Server.ShutdownTimeout <= 0 {
		problems = append(problems, "server timeouts must be positive")
	}
	if cfg.Security.APITokenFile == "" {
		problems = append(problems, "security.api_token_file is required")
	}
	if len(cfg.Security.AllowedRoots) == 0 {
		problems = append(problems, "security.allowed_roots must contain at least one directory")
	}
	for _, root := range cfg.Security.AllowedRoots {
		info, err := os.Stat(root)
		if err != nil {
			problems = append(problems, fmt.Sprintf("security.allowed_roots %q is not accessible: %v", root, err))
		} else if !info.IsDir() {
			problems = append(problems, fmt.Sprintf("security.allowed_roots %q is not a directory", root))
		}
	}
	dataPaths := []struct {
		// name 是配置字段名。
		name string
		// path 是配置字段对应的数据路径。
		path string
	}{
		{"security.api_token_file", cfg.Security.APITokenFile},
		{"database.path", cfg.Database.Path},
		{"storage.thumbnail_dir", cfg.Storage.ThumbnailDir},
		{"storage.cache_dir", cfg.Storage.CacheDir},
	}
	for _, dataPath := range dataPaths {
		for _, root := range cfg.Security.AllowedRoots {
			if pathIsWithin(root, dataPath.path) {
				problems = append(problems, fmt.Sprintf("%s must be outside read-only media root %q", dataPath.name, root))
			}
		}
	}
	if cfg.Database.Path == "" {
		problems = append(problems, "database.path is required")
	}
	if cfg.Database.BusyTimeoutMS <= 0 {
		problems = append(problems, "database.busy_timeout_ms must be positive")
	}
	if cfg.Storage.ThumbnailDir == "" || cfg.Storage.CacheDir == "" {
		problems = append(problems, "storage.thumbnail_dir and storage.cache_dir are required")
	}
	if cfg.Media.FFmpegPath == "" || cfg.Media.FFprobePath == "" {
		problems = append(problems, "media.ffmpeg_path and media.ffprobe_path are required")
	}
	if cfg.Media.ThumbnailWidth <= 0 {
		problems = append(problems, "media.thumbnail_width must be positive")
	}
	if cfg.Workers.Scan <= 0 || cfg.Workers.Probe <= 0 || cfg.Workers.Thumbnail <= 0 || cfg.Workers.LockTimeout <= 0 {
		problems = append(problems, "worker counts and workers.lock_timeout must be positive")
	}
	if len(problems) > 0 {
		return fmt.Errorf("invalid configuration: %s", strings.Join(problems, "; "))
	}
	return nil
}

// pathIsWithin 判断候选路径在词法层面是否位于指定根目录中。
func pathIsWithin(root, candidate string) bool {
	if root == "" || candidate == "" {
		return false
	}
	if runtime.GOOS == "windows" {
		root = strings.ToLower(root)
		candidate = strings.ToLower(candidate)
	}
	relative, err := filepath.Rel(filepath.Clean(root), filepath.Clean(candidate))
	if err != nil {
		return false
	}
	return relative == "." || (relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) && !filepath.IsAbs(relative))
}
