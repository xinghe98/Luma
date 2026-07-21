package media

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/platform"
)

// ThumbnailFileName 返回默认封面文件名。
func ThumbnailFileName(width int) string {
	return fmt.Sprintf("cover-%d-v1.jpg", width)
}

// ThumbnailStorageKey 返回相对于数据目录的默认缩略图存储键。
func ThumbnailStorageKey(mediaID string, width int) string {
	return filepath.ToSlash(filepath.Join("thumbnails", mediaID, ThumbnailFileName(width)))
}

// CardThumbnailFileName 返回 16:10 卡片封面的文件名。
func CardThumbnailFileName(width, height int) string {
	return fmt.Sprintf("cover-card-%dx%d-v1.jpg", width, height)
}

// CardThumbnailStorageKey 返回卡片缩略图的安全存储键。
func CardThumbnailStorageKey(mediaID string, width, height int) string {
	return filepath.ToSlash(filepath.Join("thumbnails", mediaID, CardThumbnailFileName(width, height)))
}

// resolveInputPath 安全解析媒体输入，并拒绝相对路径和链接逃逸。
func resolveInputPath(input domain.MediaInput) (string, error) {
	if !filepath.IsAbs(input.RootPath) {
		return "", fmt.Errorf("媒体源根路径必须是绝对路径")
	}
	root, err := filepath.EvalSymlinks(filepath.Clean(input.RootPath))
	if err != nil {
		return "", fmt.Errorf("解析媒体源根路径: %w", err)
	}
	info, err := os.Stat(root)
	if err != nil || !info.IsDir() {
		return "", fmt.Errorf("媒体源根路径不是可用目录")
	}
	relative, err := platform.NormalizeRelativePath(input.RelativePath)
	if err != nil {
		return "", err
	}
	candidate := filepath.Join(root, filepath.FromSlash(relative))
	resolved, err := platform.ValidateDescendant(root, candidate)
	if err != nil {
		return "", fmt.Errorf("解析媒体输入路径: %w", err)
	}
	return resolved, nil
}
