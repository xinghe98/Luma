package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
)

// StreamRepository 定义原始媒体服务所需的内容定位查询。
type StreamRepository interface {
	GetStreamLocation(context.Context, string) (domain.StreamLocation, error)
}

// ContentOpener 定义原始媒体服务所需的安全内容打开能力。
type ContentOpener interface {
	OpenContent(context.Context, string, string) (domain.OpenedContent, error)
}

// StreamService 安全打开可见原始媒体并生成 HTTP 内容元数据。
type StreamService struct {
	// repository 提供原始媒体内容定位信息。
	repository StreamRepository
	// opener 安全打开来源中的媒体内容。
	opener ContentOpener
}

// NewStreamService 创建原始媒体服务。
func NewStreamService(repository StreamRepository, opener ContentOpener) (*StreamService, error) {
	if repository == nil || opener == nil {
		return nil, errors.New("原始媒体 Repository 和内容打开器不能为空")
	}
	return &StreamService{repository: repository, opener: opener}, nil
}

// Open 返回可交给 http.ServeContent 的原始视频。
func (s *StreamService) Open(ctx context.Context, id string) (domain.StreamContent, error) {
	return s.open(ctx, id, domain.MediaTypeVideo, streamMIMEType)
}

// OpenOriginal 返回可交给 http.ServeContent 的原始图片。
func (s *StreamService) OpenOriginal(ctx context.Context, id string) (domain.StreamContent, error) {
	return s.open(ctx, id, domain.MediaTypeImage, imageMIMEType)
}

type contentMIMEType func(string, string, domain.StreamReader) (string, error)

func (s *StreamService) open(ctx context.Context, id, expectedMediaType string, resolveMIME contentMIMEType) (domain.StreamContent, error) {
	if strings.TrimSpace(id) == "" {
		return domain.StreamContent{}, fmt.Errorf("%w: 媒体 ID 无效", domain.ErrInvalidRequest)
	}
	location, err := s.repository.GetStreamLocation(ctx, id)
	if err != nil {
		return domain.StreamContent{}, err
	}
	if location.MediaType != expectedMediaType || location.SourceType != domain.SourceTypeLocal {
		return domain.StreamContent{}, domain.ErrMediaNotFound
	}
	content, err := s.opener.OpenContent(ctx, location.RootPath, location.RelativePath)
	if errors.Is(err, domain.ErrContentNotFound) {
		return domain.StreamContent{}, domain.ErrMediaNotFound
	}
	if err != nil {
		return domain.StreamContent{}, err
	}
	reader := newSizedReader(content.Reader, content.Size)
	mimeType, err := resolveMIME(location.MIMEType, location.Filename, reader)
	if err != nil {
		_ = reader.Close()
		return domain.StreamContent{}, fmt.Errorf("检测媒体 MIME: %w", err)
	}
	modifiedAt := content.ModifiedAt.UTC().Truncate(time.Second)
	return domain.StreamContent{
		Name: location.Filename, MIMEType: mimeType,
		ETag: fmt.Sprintf(`W/"%x-%x"`, content.Size, modifiedAt.Unix()),
		Size: content.Size, ModifiedAt: modifiedAt, Reader: reader,
	}, nil
}

func imageMIMEType(_ string, filename string, _ domain.StreamReader) (string, error) {
	if value := map[string]string{
		".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
		".webp": "image/webp", ".gif": "image/gif", ".bmp": "image/bmp",
	}[strings.ToLower(filepath.Ext(filename))]; value != "" {
		return value, nil
	}
	return "", fmt.Errorf("%w: 不支持的图片格式", domain.ErrMediaNotFound)
}

// sizedReader 将打开瞬间的 size 快照固定给 ServeContent，使 ETag 与 Content-Length 一致。
type sizedReader struct {
	inner domain.StreamReader
	size  int64
	off   int64
}

func newSizedReader(inner domain.StreamReader, size int64) *sizedReader {
	if size < 0 {
		size = 0
	}
	return &sizedReader{inner: inner, size: size}
}

func (r *sizedReader) Read(p []byte) (int, error) {
	if r.off >= r.size {
		return 0, io.EOF
	}
	if max := r.size - r.off; int64(len(p)) > max {
		p = p[:max]
	}
	n, err := r.inner.Read(p)
	r.off += int64(n)
	if err != nil {
		return n, err
	}
	if r.off >= r.size {
		return n, io.EOF
	}
	return n, nil
}

func (r *sizedReader) Seek(offset int64, whence int) (int64, error) {
	var abs int64
	switch whence {
	case io.SeekStart:
		abs = offset
	case io.SeekCurrent:
		abs = r.off + offset
	case io.SeekEnd:
		abs = r.size + offset
	default:
		return 0, fmt.Errorf("无效的 seek whence: %d", whence)
	}
	if abs < 0 {
		return 0, fmt.Errorf("负向 seek 位置")
	}
	target := abs
	if target > r.size {
		target = r.size
	}
	if _, err := r.inner.Seek(target, io.SeekStart); err != nil {
		return 0, err
	}
	r.off = abs
	return abs, nil
}

func (r *sizedReader) Close() error {
	return r.inner.Close()
}

func streamMIMEType(stored, filename string, reader domain.StreamReader) (string, error) {
	if value := strings.TrimSpace(stored); strings.HasPrefix(strings.ToLower(value), "video/") {
		return value, nil
	}
	extension := strings.ToLower(filepath.Ext(filename))
	if value := map[string]string{
		".mp4": "video/mp4", ".m4v": "video/x-m4v", ".mkv": "video/x-matroska",
		".mov": "video/quicktime", ".avi": "video/x-msvideo", ".webm": "video/webm", ".ts": "video/mp2t",
	}[extension]; value != "" {
		return value, nil
	}
	if value := mime.TypeByExtension(extension); value != "" {
		return value, nil
	}
	buffer := make([]byte, 512)
	n, err := reader.Read(buffer)
	if err != nil && !errors.Is(err, io.EOF) {
		return "", err
	}
	if _, err := reader.Seek(0, io.SeekStart); err != nil {
		return "", err
	}
	return http.DetectContentType(buffer[:n]), nil
}
