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

// securedInput 在外部工具运行期间保持已验证文件打开，并用于前后复核文件身份。
type securedInput struct {
	path string
	root string
	file *os.File
	info os.FileInfo
}

// openInputPath 安全打开媒体输入，拒绝链接类组件并确认句柄仍位于来源根目录。
func openInputPath(input domain.MediaInput) (*securedInput, error) {
	if !filepath.IsAbs(input.RootPath) {
		return nil, fmt.Errorf("媒体源根路径必须是绝对路径")
	}
	root, err := filepath.EvalSymlinks(filepath.Clean(input.RootPath))
	if err != nil {
		return nil, fmt.Errorf("解析媒体源根路径: %w", err)
	}
	info, err := os.Stat(root)
	if err != nil || !info.IsDir() {
		return nil, fmt.Errorf("媒体源根路径不是可用目录")
	}
	relative, err := platform.NormalizeRelativePath(input.RelativePath)
	if err != nil {
		return nil, err
	}
	candidate := filepath.Join(root, filepath.FromSlash(relative))
	if err := platform.ValidateNoLinkPath(root, candidate); err != nil {
		return nil, fmt.Errorf("媒体输入包含链接类路径组件: %w", err)
	}
	resolved, err := platform.ValidateDescendant(root, candidate)
	if err != nil {
		return nil, fmt.Errorf("解析媒体输入路径: %w", err)
	}
	file, err := os.Open(resolved)
	if err != nil {
		return nil, fmt.Errorf("打开媒体输入: %w", err)
	}
	opened, err := file.Stat()
	if err != nil {
		_ = file.Close()
		return nil, fmt.Errorf("读取媒体输入状态: %w", err)
	}
	if !opened.Mode().IsRegular() {
		_ = file.Close()
		return nil, fmt.Errorf("媒体输入不是普通文件")
	}
	if err := platform.ValidateOpenFileDescendant(root, file); err != nil {
		_ = file.Close()
		return nil, fmt.Errorf("校验媒体输入句柄: %w", err)
	}
	secured := &securedInput{path: resolved, root: root, file: file, info: opened}
	if err := secured.verify(); err != nil {
		_ = file.Close()
		return nil, err
	}
	return secured, nil
}

// verify 确认路径仍无链接类组件，且当前路径与保持打开的文件指向同一对象。
func (i *securedInput) verify() error {
	if err := platform.ValidateNoLinkPath(i.root, i.path); err != nil {
		return fmt.Errorf("媒体输入路径已被重绑定: %w", err)
	}
	current, err := os.Stat(i.path)
	if err != nil {
		return fmt.Errorf("复核媒体输入状态: %w", err)
	}
	if !os.SameFile(i.info, current) {
		return fmt.Errorf("媒体输入在外部工具执行期间发生替换")
	}
	if i.info.Size() != current.Size() || !i.info.ModTime().Equal(current.ModTime()) {
		return fmt.Errorf("媒体输入在外部工具执行期间发生内容变化")
	}
	return platform.ValidateOpenFileDescendant(i.root, i.file)
}

// Close 释放媒体处理期间保持的输入文件句柄。
func (i *securedInput) Close() error {
	return i.file.Close()
}
