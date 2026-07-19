package storage

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/platform"
)

// MaxThumbnailBytes 是单次读取缩略图允许的最大字节数。
const MaxThumbnailBytes = 8 << 20

// ThumbnailStore 将数据库逻辑存储键安全映射到缩略图目录。
type ThumbnailStore struct {
	// root 是解析符号链接后的缩略图根目录。
	root string
}

// NewThumbnailStore 创建只读缩略图存储。
func NewThumbnailStore(root string) (*ThumbnailStore, error) {
	if !filepath.IsAbs(root) {
		return nil, errors.New("缩略图目录必须是绝对路径")
	}
	resolved, err := filepath.EvalSymlinks(filepath.Clean(root))
	if err != nil {
		return nil, fmt.Errorf("解析缩略图目录: %w", err)
	}
	info, err := os.Stat(resolved)
	if err != nil || !info.IsDir() {
		return nil, errors.New("缩略图目录不可用")
	}
	return &ThumbnailStore{root: resolved}, nil
}

// Read 读取 thumbnails/ 命名空间下的普通文件并阻止链接逃逸。
func (s *ThumbnailStore) Read(storageKey string) ([]byte, error) {
	if strings.Contains(storageKey, `\`) || !strings.HasPrefix(storageKey, "thumbnails/") {
		return nil, fmt.Errorf("非法缩略图存储键")
	}
	cleaned := path.Clean(storageKey)
	if cleaned != storageKey || path.IsAbs(cleaned) || cleaned == "thumbnails" {
		return nil, fmt.Errorf("非法缩略图存储键")
	}
	relative := strings.TrimPrefix(cleaned, "thumbnails/")
	if relative == "" || relative == "." || relative == ".." || strings.HasPrefix(relative, "../") {
		return nil, fmt.Errorf("非法缩略图存储键")
	}
	candidate := filepath.Join(s.root, filepath.FromSlash(relative))
	resolved, err := platform.ValidateDescendant(s.root, candidate)
	if errors.Is(err, os.ErrNotExist) {
		return nil, domain.ErrThumbnailNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("验证缩略图路径: %w", err)
	}
	file, err := os.Open(resolved)
	if errors.Is(err, os.ErrNotExist) {
		return nil, domain.ErrThumbnailNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("打开缩略图: %w", err)
	}
	defer file.Close()
	if err := platform.ValidateOpenFileDescendant(s.root, file); err != nil {
		return nil, fmt.Errorf("验证已打开的缩略图: %w", err)
	}
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return nil, fmt.Errorf("缩略图不是可读取的普通文件")
	}
	if info.Size() > MaxThumbnailBytes {
		return nil, domain.ErrThumbnailTooLarge
	}
	data, err := io.ReadAll(io.LimitReader(file, MaxThumbnailBytes+1))
	if err != nil {
		return nil, fmt.Errorf("读取缩略图: %w", err)
	}
	if int64(len(data)) > MaxThumbnailBytes {
		return nil, domain.ErrThumbnailTooLarge
	}
	return data, nil
}
