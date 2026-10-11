//go:build !windows && !linux

package storage

import (
	"fmt"
	"os"
)

// publishByRename 在不支持硬链接的文件系统上使用平台“不覆盖”重命名发布暂存文件。
// 本实现供非 Windows/Linux 平台使用：先尝试 Root.Link，若不可用则走保守路径——
// 目标已存在即失败，不静默放宽不覆盖语义。
func (f *LocalFactory) publishByRename(root *os.Root, stage, name, stem, extension string, base UploadWriteResult) (*UploadWriteResult, error) {
	return nil, fmt.Errorf("当前平台不支持上传文件的原子不覆盖发布")
}
