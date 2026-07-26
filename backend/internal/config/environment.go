package config

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// CheckEnvironment 检查数据目录可写性以及媒体工具是否可执行。
func CheckEnvironment(ctx context.Context, cfg Config) error {
	if err := PrepareDataDirectories(cfg); err != nil {
		return err
	}
	dirs := []string{
		filepath.Dir(cfg.Database.Path),
		filepath.Dir(cfg.Security.AdminPasswordFile),
		cfg.Storage.ThumbnailDir,
		cfg.Storage.CacheDir,
	}
	for _, dir := range dirs {
		probe, err := os.CreateTemp(dir, ".luma-write-check-*")
		if err != nil {
			return fmt.Errorf("directory %q is not writable: %w", dir, err)
		}
		name := probe.Name()
		_ = probe.Close()
		_ = os.Remove(name)
	}
	for label, executable := range map[string]string{"ffmpeg": cfg.Media.FFmpegPath, "ffprobe": cfg.Media.FFprobePath} {
		path, err := exec.LookPath(executable)
		if err != nil {
			return fmt.Errorf("%s executable %q not found: %w", label, executable, err)
		}
		command := exec.CommandContext(ctx, path, "-version")
		if err := command.Run(); err != nil {
			return fmt.Errorf("run %s version check: %w", label, err)
		}
	}
	return nil
}

// PrepareDataDirectories 创建服务端运行所需的全部可写数据目录。
func PrepareDataDirectories(cfg Config) error {
	if problems := validateDataPathIsolation(cfg); len(problems) > 0 {
		return fmt.Errorf("validate data paths before creation: %s", strings.Join(problems, "; "))
	}
	dirs := []string{
		filepath.Dir(cfg.Database.Path),
		filepath.Dir(cfg.Security.AdminPasswordFile),
		cfg.Storage.ThumbnailDir,
		cfg.Storage.CacheDir,
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o750); err != nil {
			return fmt.Errorf("prepare data directory %q: %w", dir, err)
		}
	}
	return nil
}
