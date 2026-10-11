// 本文件职责：图片上传用例。
// 授权 → 来源状态 → 流式落盘 → 原子发布 → 同事务媒体索引+probe 入队；
// 任何一步失败都不留下部分发布的文件或孤儿索引。

package service

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/storage"
)

// uploadSniffBytes 是识别图片格式所需的固定前导字节数。
const uploadSniffBytes = 32

// supportedUploadExtensions 与本地扫描器保持一致，只允许扩展名做粗筛；真实判定看内容字节。
var supportedUploadExtensions = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true,
	".gif": true, ".webp": true, ".bmp": true,
}

// sniffImage 按与扫描器一致的格式清单，用文件头魔数判定真实格式。
func sniffImage(head []byte) (extension string, ok bool) {
	switch {
	case len(head) >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF:
		return ".jpg", true
	case len(head) >= 8 && bytes.Equal(head[:8], []byte{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}):
		return ".png", true
	case len(head) >= 6 && (bytes.Equal(head[:6], []byte("GIF87a")) || bytes.Equal(head[:6], []byte("GIF89a"))):
		return ".gif", true
	case len(head) >= 12 && bytes.Equal(head[:4], []byte("RIFF")) && bytes.Equal(head[8:12], []byte("WEBP")):
		return ".webp", true
	case len(head) >= 2 && head[0] == 'B' && head[1] == 'M':
		return ".bmp", true
	}
	return "", false
}

// UploadSourceChecker 定义上传用例所需的来源可见性与状态读取能力。
// 用真实的授权仓储实现，绝不允许用宽松的类型断言回退成“全部可见”。
type UploadSourceChecker interface {
	ListVisible(ctx context.Context, userID string) ([]domain.Source, error)
}

// UploadIndexer 定义上传后同步进入媒体索引并触发既有 probe 链所需的能力。
type UploadIndexer interface {
	// IndexUpload 在同一事务内把已落盘文件写进 media_items 并在需要时入队 probe。
	IndexUpload(ctx context.Context, sourceID, mediaID string, file domain.DiscoveredFile, now time.Time, probeJobID string) (domain.ReconcileResult, error)
}

// UploadNotifier 在上传索引入队 probe 后唤醒处理 Worker。
type UploadNotifier interface {
	Notify()
}

// UploadService 执行一次图片上传的完整业务序列。
type UploadService struct {
	// sources 通过授权仓储确认目标来源对当前用户可见。
	sources UploadSourceChecker
	// factory 解析来源根目录、做健康检查并安全落盘。
	factory *storage.LocalFactory
	// indexer 把发布完成的文件同步登记到媒体索引并挂接处理队列。
	indexer UploadIndexer
	// probeSignal 通知既有 probe Worker 检查持久化任务队列。
	probeSignal UploadNotifier
	// ids 生成媒体业务标识。
	ids IDGenerator
	// clock 提供统一 UTC 时间。
	clock Clock
}

// NewUploadService 组装图片上传用例；任何依赖缺失都拒绝构造。
func NewUploadService(
	sources UploadSourceChecker,
	factory *storage.LocalFactory,
	indexer UploadIndexer,
	probeSignal UploadNotifier,
	ids IDGenerator,
	clock Clock,
) (*UploadService, error) {
	if sources == nil || factory == nil || indexer == nil || probeSignal == nil || ids == nil || clock == nil {
		return nil, errors.New("上传服务依赖不能为空")
	}
	return &UploadService{
		sources: sources, factory: factory, indexer: indexer,
		probeSignal: probeSignal, ids: ids, clock: clock,
	}, nil
}

// Upload 校验授权与来源状态，把上传图片保存到来源根目录、同步进索引并挂接 probe。
// 授权在读取正文前完成；输入流直到通过授权与状态检查后才被消费。
// 失败时不留下部分发布的文件或孤儿索引；取消/超限/非法内容都返回领域错误。
func (s *UploadService) Upload(ctx context.Context, sourceID, userID string, input domain.UploadedImage) (domain.UploadResult, error) {
	if strings.TrimSpace(userID) == "" {
		return domain.UploadResult{}, domain.ErrUnauthorized
	}
	if input.Reader == nil {
		return domain.UploadResult{}, fmt.Errorf("%w: 上传内容为空", domain.ErrInvalidRequest)
	}
	// 1. 授权：只有 source_grants 明确授予的来源才可上传，在读取正文前完成。
	visible, err := s.sources.ListVisible(ctx, userID)
	if err != nil {
		return domain.UploadResult{}, err
	}
	var source *domain.Source
	for i := range visible {
		if visible[i].ID == sourceID {
			source = &visible[i]
			break
		}
	}
	if source == nil {
		return domain.UploadResult{}, domain.ErrSourceNotFound
	}
	// 2. 状态：禁用或软删除之外的非在线状态都拒绝；离线/降级也不允许写入。
	if !source.Enabled || source.Status == domain.SourceStatusDisabled {
		return domain.UploadResult{}, fmt.Errorf("%w: 媒体源已禁用", domain.ErrSourceOffline)
	}
	if source.Status != domain.SourceStatusOnline && source.Status != "" {
		return domain.UploadResult{}, fmt.Errorf("%w: 媒体源当前不可写", domain.ErrSourceOffline)
	}
	// 3. 文件名与扩展名粗筛；真实格式看头字节魔数。
	filename := storage.SanitizeUploadFilename(input.Filename)
	if filename == "" {
		return domain.UploadResult{}, fmt.Errorf("%w: 上传文件名无效", domain.ErrInvalidRequest)
	}
	extension := strings.ToLower(filepath.Ext(filename))
	if !supportedUploadExtensions[extension] {
		return domain.UploadResult{}, fmt.Errorf("%w: 不支持的图片扩展名", domain.ErrInvalidRequest)
	}
	head := make([]byte, uploadSniffBytes)
	n, err := io.ReadFull(input.Reader, head)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return domain.UploadResult{}, ctxErr
		}
		return domain.UploadResult{}, fmt.Errorf("读取上传内容: %w", err)
	}
	head = head[:n]
	sniffed, ok := sniffImage(head)
	if !ok {
		return domain.UploadResult{}, domain.ErrUploadUnsupportedImage
	}
	// jpg/jpeg 互通；其余必须和声明扩展名一致，防止“改了扩展名的另一种文件”混入。
	if sniffed != extension && !(sniffed == ".jpg" && extension == ".jpeg") {
		return domain.UploadResult{}, domain.ErrUploadUnsupportedImage
	}
	mediaID, err := s.ids.New("media")
	if err != nil {
		return domain.UploadResult{}, err
	}
	// 4. 流式落盘到隐藏暂存文件；发布前对扫描器不可见。
	pending, err := s.factory.SaveUpload(ctx, source.RootPath, filename,
		io.MultiReader(bytes.NewReader(head), input.Reader), domain.MaxUploadImageBytes)
	if err != nil {
		return domain.UploadResult{}, normalizeUploadError(err)
	}
	// 5. 调用方验证请求边界（例如无多余 multipart 部件）后才正式发布。
	if input.CommitCheck != nil {
		if checkErr := input.CommitCheck(); checkErr != nil {
			s.factory.Discard(pending)
			return domain.UploadResult{}, checkErr
		}
	}
	published, err := s.factory.Publish(ctx, pending)
	if err != nil {
		return domain.UploadResult{}, normalizeUploadError(err)
	}
	// 5. 同步进媒体索引并同事务入队 probe；失败时撤销已发布文件。
	now := s.clock.Now()
	discovered := domain.DiscoveredFile{
		RelativePath: published.RelativePath, Filename: published.Filename,
		MediaType: domain.MediaTypeImage, Size: published.Size,
		ModifiedAt: published.ModifiedAt, CreatedAt: published.CreatedAt, FileID: published.FileID,
	}
	probeJobID, err := s.ids.New("job")
	if err != nil {
		return domain.UploadResult{}, s.cleanupPublished(source.RootPath, published.RelativePath, err)
	}
	indexed, err := s.indexer.IndexUpload(ctx, source.ID, mediaID, discovered, now, probeJobID)
	if err != nil {
		return domain.UploadResult{}, s.cleanupPublished(source.RootPath, published.RelativePath, err)
	}
	s.probeSignal.Notify()
	return domain.UploadResult{MediaID: indexed.MediaID, Filename: published.Filename}, nil
}

// cleanupPublished 索引失败时删除已发布文件；清理失败与原始错误一并返回，不隐瞒孤儿文件。
func (s *UploadService) cleanupPublished(root, relative string, cause error) error {
	if rmErr := s.factory.RemoveUploaded(root, relative); rmErr != nil {
		return fmt.Errorf("%w（且清理已发布文件失败: %v，可能留有孤儿文件）", cause, rmErr)
	}
	return cause
}

// normalizeUploadError 只用 errors.Is 映射稳定的领域错误；字符串匹配不参与判定。
func normalizeUploadError(err error) error {
	switch {
	case errors.Is(err, domain.ErrUploadTooLarge),
		errors.Is(err, domain.ErrInvalidRequest),
		errors.Is(err, domain.ErrSourceOffline),
		errors.Is(err, context.Canceled),
		errors.Is(err, context.DeadlineExceeded):
		return err
	case uploadWritableError(err):
		return fmt.Errorf("%w: 媒体源不可写", domain.ErrSourceOffline)
	default:
		return err
	}
}
