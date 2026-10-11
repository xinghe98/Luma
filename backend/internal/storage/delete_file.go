// 本文件职责：从本地媒体源根目录安全删除已索引的原始文件。
// 与上传写入使用同一套安全边界：根目录经白名单重新解析并绑定 os.Root 句柄，
// 路径的每一级组件（含所有父目录与最终文件名）都拒绝符号链接与 Reparse Point，
// 最终只允许解除普通文件的目录项，绝不删除目录或跟随链接。
package storage

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"

	"github.com/xinghe98/Luma/backend/internal/platform"
)

// RemoveSourceFile 删除媒体源根目录内已索引的普通文件。
// 相对路径必须指向根目录内的常规文件；任何一级符号链接、Reparse Point、
// 目录与越界路径一律拒绝并返回 ErrContentNotFound，绝不跟随链接删除目录项之外的内容。
// 文件已不存在时返回 nil：物理删除目标已经达成，调用方可继续提交索引删除。
func (f *LocalFactory) RemoveSourceFile(ctx context.Context, root, relativePath string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	// 与 openLocalFile 相同的预校验：先按字符串规则挡住非法相对路径，
	// 再用绑定根目录句柄逐级解析，避免检查与删除之间的路径重绑定窗口。
	normalized, err := platform.NormalizeRelativePath(relativePath)
	if err != nil {
		return fmt.Errorf("%w: invalid relative path", ErrContentNotFound)
	}
	handle, err := f.openUploadRoot(root)
	if err != nil {
		return err
	}
	// 逐级下降：每级只保留一个父目录句柄，进入下一级后立即关闭旧句柄，
	// 深路径不会线性占用描述符；defer 统一兜底 early return。
	components := strings.Split(normalized, "/")
	parent := handle
	defer func() { _ = parent.Close() }()
	for _, component := range components[:len(components)-1] {
		if component == "" || component == "." || component == ".." {
			return fmt.Errorf("%w: invalid relative path", ErrContentNotFound)
		}
		info, err := parent.Lstat(component)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				// 父目录都不存在时目标必然已不在，视为删除已达成。
				return nil
			}
			return fmt.Errorf("读取待删除路径组件: %w", err)
		}
		if platform.IsLinkLike(info) || !info.IsDir() {
			return fmt.Errorf("%w: path component %q is not a regular directory", ErrContentNotFound, component)
		}
		next, err := parent.OpenRoot(component)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				return nil
			}
			return fmt.Errorf("%w: open parent directory: %v", ErrContentNotFound, err)
		}
		old := parent
		parent = next
		_ = old.Close()
	}
	// 目标必须是普通文件：目录与链接类对象直接拒绝，绝不删除目录项之外的内容。
	name := components[len(components)-1]
	if name == "" || name == "." || name == ".." {
		return fmt.Errorf("%w: invalid relative path", ErrContentNotFound)
	}
	info, err := parent.Lstat(name)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return fmt.Errorf("读取待删除文件状态: %w", err)
	}
	if info.IsDir() || platform.IsLinkLike(info) || !info.Mode().IsRegular() {
		return fmt.Errorf("%w: target is not a regular file", ErrContentNotFound)
	}
	// 最终解除目录项走平台私有实现：相对父目录句柄原子拒绝目录，
	// 检查与删除之间目标被换成目录也不会误删目录项。
	if err := removeRegularFile(parent, name); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			// 并发扫描或其他删除者已先行移除文件，物理目标同样达成。
			return nil
		}
		return fmt.Errorf("删除媒体文件: %w", err)
	}
	return nil
}
