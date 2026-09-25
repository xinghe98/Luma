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
	GetStreamLocation(context.Context, string, string) (domain.StreamLocation, error)
}

// ContentOpener 定义原始媒体服务所需的安全内容打开能力。
type ContentOpener interface {
	OpenContent(context.Context, string, string) (domain.OpenedContent, error)
}

// StreamFaststartCache 决定一次播放固定的文件表示，并打开该表示对应的 faststart 副本。
// 选择表示必须立即返回：缓存未命中时只排队后台预热，不能等待 remux。
type StreamFaststartCache interface {
	SelectRepresentation(domain.StreamLocation, domain.OpenedContent) domain.StreamTarget
	OpenFaststart(domain.StreamLocation, domain.OpenedContent, string) (domain.OpenedContent, error)
}

// StreamService 安全打开可见原始媒体并生成 HTTP 内容元数据。
type StreamService struct {
	// repository 提供原始媒体内容定位信息。
	repository StreamRepository
	// opener 安全打开来源中的媒体内容。
	opener ContentOpener
	// faststart 可选；视频入口依据它固定表示并打开缓存副本。
	faststart StreamFaststartCache
}

// NewStreamService 创建原始媒体服务。
func NewStreamService(repository StreamRepository, opener ContentOpener) (*StreamService, error) {
	if repository == nil || opener == nil {
		return nil, errors.New("原始媒体 Repository 和内容打开器不能为空")
	}
	return &StreamService{repository: repository, opener: opener}, nil
}

// SetFaststartCache 设置 faststart 缓存协作器；允许为空，此时视频入口始终固定为原始文件。
func (s *StreamService) SetFaststartCache(cache StreamFaststartCache) {
	s.faststart = cache
}

// Plan 决定一次播放固定的文件表示，并且总是立即返回。
// 缓存已就绪时固定 faststart 副本，否则固定原始文件并触发后台预热。
func (s *StreamService) Plan(ctx context.Context, id, userID string) (domain.StreamTarget, error) {
	location, err := s.locate(ctx, id, userID, domain.MediaTypeVideo)
	if err != nil {
		return domain.StreamTarget{}, err
	}
	source, err := s.openSource(ctx, location)
	if err != nil {
		return domain.StreamTarget{}, err
	}
	if source.Reader != nil {
		defer func() { _ = source.Reader.Close() }()
	}
	if s.faststart == nil {
		return domain.StreamTarget{Representation: domain.StreamRepresentationSource}, nil
	}
	return s.faststart.SelectRepresentation(location, source), nil
}

// OpenSource 打开原始视频文件；该表示与预热进度无关，始终返回源文件字节。
func (s *StreamService) OpenSource(ctx context.Context, id, userID string) (domain.StreamContent, error) {
	location, err := s.locate(ctx, id, userID, domain.MediaTypeVideo)
	if err != nil {
		return domain.StreamContent{}, err
	}
	source, err := s.openSource(ctx, location)
	if err != nil {
		return domain.StreamContent{}, err
	}
	return s.present(location, source, streamMIMEType)
}

// OpenFaststart 打开入口固定的 faststart 副本。
// 副本不可用或指纹不再对应当前源文件时明确失败，绝不回退到原始文件字节。
func (s *StreamService) OpenFaststart(ctx context.Context, id, userID, fingerprint string) (domain.StreamContent, error) {
	location, err := s.locate(ctx, id, userID, domain.MediaTypeVideo)
	if err != nil {
		return domain.StreamContent{}, err
	}
	if s.faststart == nil {
		return domain.StreamContent{}, domain.ErrStreamCacheMiss
	}
	// 源文件快照只用于核对副本指纹并复查访问权限，随后立即关闭原始文件句柄。
	source, err := s.openSource(ctx, location)
	if err != nil {
		return domain.StreamContent{}, err
	}
	if source.Reader != nil {
		defer func() { _ = source.Reader.Close() }()
	}
	content, err := s.faststart.OpenFaststart(location, source, fingerprint)
	if err != nil {
		return domain.StreamContent{}, err
	}
	return s.present(location, content, streamMIMEType)
}

// OpenOriginal 返回可交给 http.ServeContent 的原始图片。
func (s *StreamService) OpenOriginal(ctx context.Context, id, userID string) (domain.StreamContent, error) {
	location, err := s.locate(ctx, id, userID, domain.MediaTypeImage)
	if err != nil {
		return domain.StreamContent{}, err
	}
	source, err := s.openSource(ctx, location)
	if err != nil {
		return domain.StreamContent{}, err
	}
	return s.present(location, source, imageMIMEType)
}

// contentMIMEType 依据存储 MIME、文件名与内容快照解析响应 MIME。
type contentMIMEType func(string, string, domain.StreamReader) (string, error)

// locate 校验请求参数并返回当前用户可见的媒体定位信息。
func (s *StreamService) locate(ctx context.Context, id, userID, expectedMediaType string) (domain.StreamLocation, error) {
	if strings.TrimSpace(id) == "" || strings.TrimSpace(userID) == "" {
		return domain.StreamLocation{}, fmt.Errorf("%w: 媒体 ID 无效", domain.ErrInvalidRequest)
	}
	location, err := s.repository.GetStreamLocation(ctx, id, userID)
	if err != nil {
		return domain.StreamLocation{}, err
	}
	if location.MediaType != expectedMediaType || location.SourceType != domain.SourceTypeLocal {
		return domain.StreamLocation{}, domain.ErrMediaNotFound
	}
	return location, nil
}

// openSource 通过安全打开器取得源文件快照；调用方负责关闭返回的 Reader。
func (s *StreamService) openSource(ctx context.Context, location domain.StreamLocation) (domain.OpenedContent, error) {
	content, err := s.opener.OpenContent(ctx, location.RootPath, location.RelativePath)
	if errors.Is(err, domain.ErrContentNotFound) {
		return domain.OpenedContent{}, domain.ErrMediaNotFound
	}
	if err != nil {
		return domain.OpenedContent{}, err
	}
	return content, nil
}

// present 按内容快照固定大小并解析 MIME；调用方负责关闭返回的 Reader。
func (s *StreamService) present(location domain.StreamLocation, content domain.OpenedContent, resolveMIME contentMIMEType) (domain.StreamContent, error) {
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
