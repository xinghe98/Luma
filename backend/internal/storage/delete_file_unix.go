//go:build unix

// 本文件提供类 Unix 平台的媒体文件解除目录项实现：相对父目录句柄执行
// unlinkat（不带 AT_REMOVEDIR），目录目标在 syscall 层面即被拒绝，
// 检查与删除之间目标被换成目录也不会误删目录。
package storage

import (
	"fmt"
	"os"

	"golang.org/x/sys/unix"
)

// removeRegularFile 相对父目录句柄解除普通文件的目录项。
// 不传 AT_REMOVEDIR 时 unlinkat 对目录返回 EISDIR（Linux）或 EPERM，
// 与外层 Lstat 校验叠加后形成无窗口的“只删普通文件”约束；
// EPERM 也可能来自粘滞目录权限拒绝，保留原始错误不误报“文件不存在”。
func removeRegularFile(parent *os.Root, name string) error {
	directory, err := parent.Open(".")
	if err != nil {
		return err
	}
	defer directory.Close()
	if err := unix.Unlinkat(int(directory.Fd()), name, 0); err != nil {
		if err == unix.EISDIR {
			return fmt.Errorf("%w: target is not a regular file", ErrContentNotFound)
		}
		return err
	}
	return nil
}
