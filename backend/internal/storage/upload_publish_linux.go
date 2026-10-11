//go:build linux

// 本文件提供不覆盖的 Linux 上传发布；重命名始终相对于暂存文件所属目录句柄。
package storage

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/sys/unix"
)

// publishByRename 在硬链接不可用（如 FAT/exFAT 媒体目录）时退化为
// renameat2(RENAME_NOREPLACE)，目标已存在即失败，保持“绝不覆盖”语义；
// 暂存与目标位于同一目录，重命名始终同卷。
func (f *LocalFactory) publishByRename(root *os.Root, stage, name, stem, extension string, base UploadWriteResult) (*UploadWriteResult, error) {
	directory, err := root.Open(".")
	if err != nil {
		return nil, err
	}
	defer directory.Close()
	dirFD := int(directory.Fd())
	for i := range 256 {
		candidate := name
		if i > 0 {
			candidate = fmt.Sprintf("%s (%d)%s", stem, i+1, extension)
		}
		err := unix.Renameat2(dirFD, stage, dirFD, candidate, unix.RENAME_NOREPLACE)
		switch {
		case err == nil:
			result := base
			result.Filename = candidate
			result.RelativePath = filepath.ToSlash(candidate)
			return &result, nil
		case errors.Is(err, unix.EEXIST):
			continue
		case errors.Is(err, unix.ENOSYS) || errors.Is(err, unix.EINVAL):
			// 内核或文件系统不支持 renameat2 flags：没有可靠的“不覆盖重命名”，
			// 明确报错而不是放宽语义或接受部分发布。
			return nil, fmt.Errorf("当前平台不支持上传文件的原子不覆盖发布: %w", err)
		default:
			return nil, fmt.Errorf("发布上传文件: %w", err)
		}
	}
	return nil, fmt.Errorf("无法为上传文件选择安全名称")
}
