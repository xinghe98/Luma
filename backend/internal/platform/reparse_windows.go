//go:build windows

package platform

import (
	"os"
	"syscall"
)

// IsLinkLike 判断文件是否为符号链接、Junction 或其他 Reparse Point。
func IsLinkLike(info os.FileInfo) bool {
	if info.Mode()&os.ModeSymlink != 0 {
		return true
	}
	data, ok := info.Sys().(*syscall.Win32FileAttributeData)
	return ok && data.FileAttributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0
}
