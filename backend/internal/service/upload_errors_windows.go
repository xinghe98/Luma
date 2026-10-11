//go:build windows

package service

import (
	"errors"
	"os"

	"golang.org/x/sys/windows"
)

// uploadWritableError 判断错误是否属于“媒体源不可写”。
// Windows 只读媒体返回 ERROR_ACCESS_DENIED（已含在 os.ErrPermission 链内），
// 只读文件系统属性目录会返回 ERROR_FILE_READ_ONLY。
func uploadWritableError(err error) bool {
	return errors.Is(err, os.ErrPermission) ||
		errors.Is(err, windows.ERROR_FILE_READ_ONLY) ||
		errors.Is(err, windows.ERROR_WRITE_PROTECT)
}
