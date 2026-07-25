package scanner

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

// LocalScanner 根据扩展名筛选本地媒体源中的视频和图片。
type LocalScanner struct {
	// extensions 保存小写扩展名到媒体类型的映射。
	extensions map[string]string
}

// NewLocalScanner 使用配置的扩展名创建媒体扫描器。
func NewLocalScanner(extensions []string) (*LocalScanner, error) {
	known := defaultMediaExtensions()
	selected := make(map[string]string, len(extensions))
	for _, extension := range extensions {
		normalized := strings.TrimPrefix(strings.ToLower(strings.TrimSpace(extension)), ".")
		mediaType, ok := known[normalized]
		if !ok {
			return nil, fmt.Errorf("不支持的扫描扩展名 %q", extension)
		}
		selected[normalized] = mediaType
	}
	if len(selected) == 0 {
		return nil, fmt.Errorf("扫描扩展名不能为空")
	}
	return &LocalScanner{extensions: selected}, nil
}

// Scan 遍历媒体源，并仅将配置支持的普通媒体文件传给回调。
func (s *LocalScanner) Scan(ctx context.Context, source storage.MediaSource, visit func(domain.DiscoveredFile) error) error {
	if source == nil || visit == nil {
		return fmt.Errorf("媒体源和扫描回调不能为空")
	}
	return source.Walk(ctx, func(entry storage.FileEntry) error {
		// macOS 在非 Apple 文件系统上生成的 AppleDouble 辅助文件不是媒体内容。
		if strings.HasPrefix(entry.Filename, "._") {
			return nil
		}
		extension := strings.TrimPrefix(strings.ToLower(filepath.Ext(entry.Filename)), ".")
		mediaType, ok := s.extensions[extension]
		if !ok {
			return nil
		}
		return visit(domain.DiscoveredFile{
			RelativePath: entry.RelativePath, Filename: entry.Filename,
			MediaType: mediaType, Size: entry.Size,
			ModifiedAt: entry.ModifiedAt, FileID: entry.FileID,
		})
	})
}

// defaultMediaExtensions 返回架构文档规定的 V1 媒体扩展名映射。
func defaultMediaExtensions() map[string]string {
	return map[string]string{
		"mp4": domain.MediaTypeVideo, "mkv": domain.MediaTypeVideo,
		"mov": domain.MediaTypeVideo, "avi": domain.MediaTypeVideo,
		"webm": domain.MediaTypeVideo, "m4v": domain.MediaTypeVideo,
		"ts":  domain.MediaTypeVideo,
		"jpg": domain.MediaTypeImage, "jpeg": domain.MediaTypeImage,
		"png": domain.MediaTypeImage, "webp": domain.MediaTypeImage,
		"gif": domain.MediaTypeImage, "bmp": domain.MediaTypeImage,
		"nfo": domain.MediaTypeSidecar,
	}
}
