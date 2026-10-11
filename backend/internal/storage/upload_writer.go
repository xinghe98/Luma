// 本文件职责：向本地媒体源根目录安全写入上传文件。
// 所有文件操作都通过 os.Root 绑定的目录句柄做相对路径调用，
// 路径重绑定、符号链接与根目录替换都不能把内容写到来源根之外。
// 上传只写来源根目录的顶层文件名，不接受客户端传入的任何目录成分。
package storage

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/platform"
)

// UploadWriteResult 描述一次落盘完成的文件，供媒体索引直接采用。
type UploadWriteResult struct {
	// RelativePath 是媒体源根目录到落盘文件的规范化相对路径（恒为文件名本身）。
	RelativePath string
	// Filename 是实际落盘文件名；与请求同名冲突时自动加安全后缀。
	Filename string
	// Size 是写入完成的字节数。
	Size int64
	// ModifiedAt 是落盘完成时的真实文件修改时间。
	ModifiedAt time.Time
	// CreatedAt 是文件创建时间；文件系统未提供时为 nil。
	CreatedAt *time.Time
	// FileID 是平台稳定文件身份；不可得时为空。
	FileID string
}

// PendingUpload 持有已完整写入、尚未发布的暂存文件句柄。
// 调用方负责 Publish 或 Discard；句柄脱离 PendingUpload 后不再使用。
type PendingUpload struct {
	// root 是打开媒体源根目录的句柄；发布前目录重绑定不影响写入目标。
	root *os.Root
	// stageName 是根目录内的隐藏暂存文件名。
	stageName string
	// result 是写入完成时刻的文件元数据快照。
	result UploadWriteResult
}

// isHardlinkUnsupported 判断底层文件系统是否不支持硬链接，无法保证原子发布。
func isHardlinkUnsupported(err error) bool {
	return errors.Is(err, errHardlinkUnsupported)
}

// sanitizeUploadFilename 只保留 basename 并剥离不安全的开头字符。
// 返回空串表示请求文件名不可用。
func sanitizeUploadFilename(name string) string {
	base := filepath.Base(strings.ReplaceAll(name, "\\", "/"))
	if base == "/" || base == "\\" || base == "." {
		return ""
	}
	base = strings.TrimLeft(base, ".")
	base = strings.TrimSpace(base)
	if strings.ContainsAny(base, "\x00/\\") {
		return ""
	}
	return base
}

// SanitizeUploadFilename 供业务层做与落盘一致的文件名粗筛。
func SanitizeUploadFilename(name string) string { return sanitizeUploadFilename(name) }

// uploadCopyBufferSize 是落盘复制的固定缓冲；不随上传大小增长。
const uploadCopyBufferSize = 256 << 10

// uploadStageAttempts 是选择唯一暂存文件名的最大尝试次数。
const uploadStageAttempts = 64

// openUploadRoot 复用媒体源根目录解析并把目录绑定为 os.Root 句柄。
func (f *LocalFactory) openUploadRoot(root string) (*os.Root, error) {
	resolved, err := f.resolveRoot(root)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", domain.ErrSourceOffline, err)
	}
	handle, err := os.OpenRoot(resolved)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", domain.ErrSourceOffline, err)
	}
	return handle, nil
}

// SaveUpload 把上传流式内容完整写入媒体源根目录内的隐藏暂存文件。
// 文件全程对扫描器不可见（无媒体扩展名且以点开头）；任何失败都会删除暂存文件。
// 返回的 PendingUpload 仍持有根目录句柄，发布前根目录重绑定不影响结果。
func (f *LocalFactory) SaveUpload(ctx context.Context, root, filename string, content io.Reader, limit int64) (*PendingUpload, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	handle, err := f.openUploadRoot(root)
	if err != nil {
		return nil, err
	}
	defer func() {
		if handle != nil {
			_ = handle.Close()
		}
	}()
	name := sanitizeUploadFilename(filename)
	if name == "" {
		return nil, fmt.Errorf("%w: 上传文件名无效", domain.ErrInvalidRequest)
	}
	// 暂存文件名随机化且带 O_EXCL 创建，天然不占用任何已存在路径。
	stage, stageName, err := createUploadStage(handle)
	if err != nil {
		return nil, err
	}
	discard := func(cause error) (*PendingUpload, error) {
		_ = stage.Close()
		_ = handle.Remove(stageName)
		return nil, cause
	}
	limited := &io.LimitedReader{R: content, N: limit + 1}
	buffer := make([]byte, uploadCopyBufferSize)
	written, err := io.CopyBuffer(stage, limited, buffer)
	if err != nil {
		if ctxErr := ctx.Err(); ctxErr != nil {
			return discard(ctxErr)
		}
		return discard(fmt.Errorf("写入上传内容: %w", err))
	}
	if err := ctx.Err(); err != nil {
		return discard(err)
	}
	if written > limit {
		return discard(domain.ErrUploadTooLarge)
	}
	if err := stage.Sync(); err != nil {
		return discard(fmt.Errorf("同步上传暂存文件: %w", err))
	}
	info, err := stage.Stat()
	if err != nil {
		return discard(fmt.Errorf("读取上传暂存状态: %w", err))
	}
	if !info.Mode().IsRegular() {
		return discard(fmt.Errorf("上传暂存文件不是普通文件"))
	}
	if err := stage.Close(); err != nil {
		_ = handle.Remove(stageName)
		return nil, fmt.Errorf("关闭上传暂存文件: %w", err)
	}
	absolute := filepath.Join(handle.Name(), stageName)
	fileID, _ := f.identifiers.Identify(absolute)
	pending := &PendingUpload{
		root: handle, stageName: stageName,
		result: UploadWriteResult{
			Filename: name, Size: written,
			ModifiedAt: info.ModTime().UTC(),
			CreatedAt:  platform.FileCreatedAt(absolute, info),
			FileID:     fileID,
		},
	}
	handle = nil // 所有权移交 PendingUpload。
	return pending, nil
}

// createUploadStage 用随机隐藏名在根目录内创建独占暂存文件。
func createUploadStage(root *os.Root) (*os.File, string, error) {
	var random [8]byte
	for range uploadStageAttempts {
		if _, err := rand.Read(random[:]); err != nil {
			return nil, "", fmt.Errorf("生成上传暂存名: %w", err)
		}
		name := ".luma-upload-" + hex.EncodeToString(random[:])
		file, err := root.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
		if err == nil {
			return file, name, nil
		}
		if !errors.Is(err, os.ErrExist) {
			return nil, "", fmt.Errorf("创建上传暂存文件: %w", err)
		}
	}
	return nil, "", fmt.Errorf("无法创建上传暂存文件")
}

// Publish 把暂存文件原子发布为请求文件名；同名已存在时自动挑选 “name (2).ext”
// 后缀重试，绝不覆盖既有文件。发布成功后 PendingUpload 不再可用。
// 优先使用硬链接（原子且不依赖平台 rename 语义）；文件系统不支持硬链接时
// 回退到平台原生“不覆盖重命名”，两者都不可用时返回错误而不是静默放宽。
func (f *LocalFactory) Publish(ctx context.Context, pending *PendingUpload) (*UploadWriteResult, error) {
	if pending == nil || pending.root == nil {
		return nil, fmt.Errorf("上传暂存状态无效")
	}
	root := pending.root
	stage := pending.stageName
	pending.root = nil
	pending.stageName = ""
	defer root.Close()
	if err := ctx.Err(); err != nil {
		_ = root.Remove(stage)
		return nil, err
	}
	name := pending.result.Filename
	extension := filepath.Ext(name)
	stem := strings.TrimSuffix(name, extension)
	for i := range 256 {
		candidate := name
		if i > 0 {
			candidate = fmt.Sprintf("%s (%d)%s", stem, i+1, extension)
		}
		err := root.Link(stage, candidate)
		switch {
		case err == nil:
			// 发布成功后暂存名与最终名是同一文件的硬链接，移除暂存名即可；
			// 清理失败只遗留一个不可见名称，不视为失败。
			_ = root.Remove(stage)
			result := pending.result
			result.Filename = candidate
			result.RelativePath = filepath.ToSlash(candidate)
			return &result, nil
		case errors.Is(err, os.ErrExist):
			continue
		case isHardlinkUnsupported(err):
			published, pubErr := f.publishByRename(root, stage, name, stem, extension, pending.result)
			if pubErr == nil {
				return published, nil
			}
			_ = root.Remove(stage)
			return nil, pubErr
		default:
			_ = root.Remove(stage)
			return nil, fmt.Errorf("发布上传文件: %w", err)
		}
	}
	_ = root.Remove(stage)
	return nil, fmt.Errorf("无法为上传文件选择安全名称")
}

// Discard 删除未发布的暂存文件；Publish 成功后不要再调用。
func (f *LocalFactory) Discard(pending *PendingUpload) {
	if pending == nil || pending.root == nil {
		return
	}
	_ = pending.root.Remove(pending.stageName)
	_ = pending.root.Close()
	pending.root = nil
	pending.stageName = ""
}

// RemoveUploaded 删除已发布到媒体源根目录的上传文件；仅供索引失败后的补偿清理。
// 只接受根目录下的单级文件名，重新经 os.Root 校验后才解除链接。
// 删除失败会返回错误，由调用方决定是否上报“可能留有孤儿文件”。
func (f *LocalFactory) RemoveUploaded(root, relative string) error {
	handle, err := f.openUploadRoot(root)
	if err != nil {
		return err
	}
	defer handle.Close()
	normalized, err := platform.NormalizeRelativePath(relative)
	if err != nil {
		return err
	}
	if strings.Contains(normalized, "/") {
		return fmt.Errorf("上传清理只接受顶层文件名")
	}
	return handle.Remove(normalized)
}
