package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/xinghe98/Luma/backend/internal/domain"
	"github.com/xinghe98/Luma/backend/internal/platform"
)

// LocalFactory 使用平台文件身份实现创建只读本地媒体源。
type LocalFactory struct {
	// identifiers 是注入的文件身份读取器。
	identifiers FileIdentifier
	// clock 是注入的 UTC 时钟。
	clock Clock
	// roots 在每次解析根目录时重新应用当前白名单策略。
	roots SourceRootValidator
}

// SourceRootValidator 定义本地存储重新解析来源根目录时使用的白名单检查。
type SourceRootValidator interface {
	// ValidateSourceRoot 返回当前白名单内的最终目录；目录重绑定或越界时返回错误。
	ValidateSourceRoot(string) (string, error)
}

// NewLocalFactory 使用文件身份、时钟和可选路径策略创建工厂；生产调用必须注入路径策略。
func NewLocalFactory(identifiers FileIdentifier, clock Clock, roots ...SourceRootValidator) (*LocalFactory, error) {
	if identifiers == nil || clock == nil {
		return nil, fmt.Errorf("文件身份读取器和时钟不能为空")
	}
	if len(roots) > 1 || (len(roots) == 1 && roots[0] == nil) {
		return nil, fmt.Errorf("媒体源路径策略无效")
	}
	factory := &LocalFactory{identifiers: identifiers, clock: clock}
	if len(roots) == 1 {
		factory.roots = roots[0]
	}
	return factory, nil
}

// Local 创建并校验一个只读本地媒体源。
func (f *LocalFactory) Local(root string) (MediaSource, error) {
	resolved, err := f.resolveRoot(root)
	if err != nil {
		return nil, err
	}
	return &LocalSource{root: resolved, identifiers: f.identifiers, clock: f.clock}, nil
}

func (f *LocalFactory) resolveRoot(root string) (string, error) {
	if f.roots != nil {
		resolved, err := f.roots.ValidateSourceRoot(root)
		if err != nil {
			return "", fmt.Errorf("重新校验媒体源根目录: %w", err)
		}
		return resolved, nil
	}
	resolved, err := filepath.EvalSymlinks(root)
	if err != nil {
		return "", fmt.Errorf("解析媒体源根目录: %w", err)
	}
	info, err := os.Stat(resolved)
	if err != nil {
		return "", fmt.Errorf("读取媒体源根目录: %w", err)
	}
	if !info.IsDir() {
		return "", fmt.Errorf("媒体源根路径不是目录")
	}
	resolved = filepath.Clean(resolved)
	return resolved, nil
}

// LocalSource 以只读方式遍历和打开操作系统本地目录。
type LocalSource struct {
	// root 是解析链接后的媒体源根目录。
	root string
	// identifiers 是平台文件身份读取器。
	identifiers FileIdentifier
	// clock 是注入的 UTC 时钟。
	clock Clock
}

// Walk 遍历媒体源内的普通文件，并拒绝链接和 Reparse Point。
func (s *LocalSource) Walk(ctx context.Context, visit func(FileEntry) error) error {
	return filepath.WalkDir(s.root, func(path string, entry os.DirEntry, walkErr error) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		if walkErr != nil {
			return walkErr
		}
		if path == s.root {
			return nil
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if platform.IsLinkLike(info) {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if entry.IsDir() {
			return nil
		}
		if !info.Mode().IsRegular() {
			return nil
		}
		resolved, err := platform.ValidateDescendant(s.root, path)
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(s.root, resolved)
		if err != nil {
			return err
		}
		relative, err = platform.NormalizeRelativePath(relative)
		if err != nil {
			return err
		}
		fileID, _ := s.identifiers.Identify(resolved)
		return visit(FileEntry{
			RelativePath: relative, Filename: entry.Name(), Size: info.Size(),
			ModifiedAt: info.ModTime().UTC(), FileID: fileID,
		})
	})
}

// Open 校验最终路径仍在根目录内后，以只读方式打开媒体文件。
func (s *LocalSource) Open(ctx context.Context, relativePath string) (ReadSeekCloser, error) {
	file, _, err := openLocalFile(ctx, s.root, relativePath)
	return file, err
}

// OpenContent 安全打开媒体源内的普通文件，并返回打开瞬间的元数据快照。
func (f *LocalFactory) OpenContent(ctx context.Context, root, relativePath string) (domain.OpenedContent, error) {
	if err := ctx.Err(); err != nil {
		return domain.OpenedContent{}, err
	}
	resolved, err := f.resolveRoot(root)
	if err != nil {
		return domain.OpenedContent{}, fmt.Errorf("%w: source root is unavailable", domain.ErrSourceOffline)
	}
	file, info, err := openLocalFile(ctx, resolved, relativePath)
	if err != nil {
		if errors.Is(err, ErrContentNotFound) {
			return domain.OpenedContent{}, err
		}
		return domain.OpenedContent{}, err
	}
	return domain.OpenedContent{
		Reader: file, Size: info.Size(), ModifiedAt: info.ModTime().UTC(),
	}, nil
}

func openLocalFile(ctx context.Context, root, relativePath string) (*os.File, os.FileInfo, error) {
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	normalized, err := platform.NormalizeRelativePath(relativePath)
	if err != nil {
		return nil, nil, fmt.Errorf("%w: invalid relative path", ErrContentNotFound)
	}
	candidate := filepath.Join(root, filepath.FromSlash(normalized))
	if err := platform.ValidateNoLinkPath(root, candidate); err != nil {
		return nil, nil, fmt.Errorf("%w: path contains a link-like component", ErrContentNotFound)
	}
	resolved, err := platform.ValidateDescendant(root, candidate)
	if err != nil {
		return nil, nil, fmt.Errorf("%w: path validation failed", ErrContentNotFound)
	}
	file, err := os.Open(resolved)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil, fmt.Errorf("%w: file does not exist", ErrContentNotFound)
		}
		return nil, nil, err
	}
	if err := platform.ValidateOpenFileDescendant(root, file); err != nil {
		_ = file.Close()
		return nil, nil, fmt.Errorf("%w: opened file failed validation", ErrContentNotFound)
	}
	info, err := file.Stat()
	if err != nil {
		_ = file.Close()
		if errors.Is(err, os.ErrNotExist) {
			return nil, nil, fmt.Errorf("%w: file does not exist", ErrContentNotFound)
		}
		return nil, nil, err
	}
	if !info.Mode().IsRegular() {
		_ = file.Close()
		return nil, nil, fmt.Errorf("%w: content is not a regular file", ErrContentNotFound)
	}
	return file, info, nil
}

// Health 检查媒体源根目录当前是否存在且可读取。
func (s *LocalSource) Health(ctx context.Context) (SourceHealth, error) {
	if err := ctx.Err(); err != nil {
		return SourceHealth{}, err
	}
	file, err := os.Open(s.root)
	if err != nil {
		return SourceHealth{Online: false, CheckedAt: s.clock.Now()}, err
	}
	defer file.Close()
	if _, err := file.Readdirnames(1); err != nil && !errors.Is(err, io.EOF) {
		// 空目录返回 io.EOF，同样代表目录可读。
		return SourceHealth{Online: false, CheckedAt: s.clock.Now()}, err
	}
	return SourceHealth{Online: true, CheckedAt: s.clock.Now()}, nil
}
