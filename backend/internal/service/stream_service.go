package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os/exec"
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

// StreamService 安全打开可见原始媒体并生成 HTTP 内容元数据。
type StreamService struct {
	// repository 提供原始媒体内容定位信息。
	repository StreamRepository
	// opener 安全打开来源中的媒体内容。
	opener ContentOpener
	// ffmpegPath 是 ffmpeg 可执行文件路径。
	ffmpegPath string
}

// NewStreamService 创建原始媒体服务。
func NewStreamService(repository StreamRepository, opener ContentOpener) (*StreamService, error) {
	if repository == nil || opener == nil {
		return nil, errors.New("原始媒体 Repository 和内容打开器不能为空")
	}
	return &StreamService{repository: repository, opener: opener, ffmpegPath: "ffmpeg"}, nil
}

// SetFFmpegPath 设置用于音频实时转码的 FFmpeg 命令路径。
func (s *StreamService) SetFFmpegPath(path string) {
	if strings.TrimSpace(path) != "" {
		s.ffmpegPath = path
	}
}

// IsAudioTranscodeRequired 检查指定音频编码格式是否为原生播放器通常无法解码的格式。
func IsAudioTranscodeRequired(codec string) bool {
	switch strings.ToLower(strings.TrimSpace(codec)) {
	case "dts", "dca", "ac3", "eac3", "truehd", "mlp":
		return true
	default:
		return false
	}
}

// GetLocation 获取可见原始媒体定位信息。
func (s *StreamService) GetLocation(ctx context.Context, id, userID string) (domain.StreamLocation, error) {
	return s.repository.GetStreamLocation(ctx, id, userID)
}

// OpenTranscodeStream 启动 FFmpeg 将音频实时转码为双声道 AAC 并输出 fMP4 管道流。
func (s *StreamService) OpenTranscodeStream(ctx context.Context, id, userID string) (io.ReadCloser, string, error) {
	if strings.TrimSpace(id) == "" || strings.TrimSpace(userID) == "" {
		return nil, "", fmt.Errorf("%w: 媒体 ID 无效", domain.ErrInvalidRequest)
	}
	location, err := s.repository.GetStreamLocation(ctx, id, userID)
	if err != nil {
		return nil, "", err
	}
	if location.MediaType != domain.MediaTypeVideo || location.SourceType != domain.SourceTypeLocal {
		return nil, "", domain.ErrMediaNotFound
	}
	fullPath := filepath.Join(location.RootPath, location.RelativePath)
	ffmpegExec := s.ffmpegPath
	if ffmpegExec == "" {
		ffmpegExec = "ffmpeg"
	}
	cmd := exec.CommandContext(ctx, ffmpegExec,
		"-v", "error",
		"-i", fullPath,
		"-c:v", "copy",
		"-c:a", "aac",
		"-ac", "2",
		"-b:a", "192k",
		"-f", "mp4",
		"-movflags", "frag_keyframe+empty_moov",
		"pipe:1",
	)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, "", fmt.Errorf("创建 FFmpeg 转码管道失败: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return nil, "", fmt.Errorf("启动 FFmpeg 音频转码失败: %w", err)
	}
	reader := &transcodeStreamReader{
		cmd:    cmd,
		stdout: stdout,
	}
	return reader, "video/mp4", nil
}

type transcodeStreamReader struct {
	cmd    *exec.Cmd
	stdout io.ReadCloser
}

func (r *transcodeStreamReader) Read(p []byte) (int, error) {
	return r.stdout.Read(p)
}

func (r *transcodeStreamReader) Close() error {
	_ = r.stdout.Close()
	if r.cmd != nil && r.cmd.Process != nil {
		_ = r.cmd.Process.Kill()
		_ = r.cmd.Wait()
	}
	return nil
}

// Open 返回可交给 http.ServeContent 的原始视频。
func (s *StreamService) Open(ctx context.Context, id, userID string) (domain.StreamContent, error) {
	return s.open(ctx, id, userID, domain.MediaTypeVideo, streamMIMEType)
}

// OpenOriginal 返回可交给 http.ServeContent 的原始图片。
func (s *StreamService) OpenOriginal(ctx context.Context, id, userID string) (domain.StreamContent, error) {
	return s.open(ctx, id, userID, domain.MediaTypeImage, imageMIMEType)
}

type contentMIMEType func(string, string, domain.StreamReader) (string, error)

func (s *StreamService) open(ctx context.Context, id, userID, expectedMediaType string, resolveMIME contentMIMEType) (domain.StreamContent, error) {
	if strings.TrimSpace(id) == "" || strings.TrimSpace(userID) == "" {
		return domain.StreamContent{}, fmt.Errorf("%w: 媒体 ID 无效", domain.ErrInvalidRequest)
	}
	location, err := s.repository.GetStreamLocation(ctx, id, userID)
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
