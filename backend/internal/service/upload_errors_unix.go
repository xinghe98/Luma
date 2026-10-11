//go:build !windows

package service

import (
	"errors"
	"os"
	"syscall"
)

// uploadWritableError 判断错误是否属于“媒体源不可写”（只读文件系统或权限拒绝）。
func uploadWritableError(err error) bool {
	return errors.Is(err, os.ErrPermission) || errors.Is(err, syscall.EROFS)
}
